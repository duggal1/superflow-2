import Foundation
import SuperflowKernel
import SuperflowPorts

public struct ChunkOutcome: Sendable, Equatable {
    public var index: Int
    public var text: String
    public var state: CleanupState
    public var tokensIn: Int
    public var tokensOut: Int
    public var latencyMs: Int
    public var attempts: Int
    public var prefillMs: Int?
    public var generationMs: Int?
    public var reason: String?
    public init(index: Int, text: String, state: CleanupState, tokensIn: Int = 0, tokensOut: Int = 0,
                latencyMs: Int = 0, attempts: Int = 0, reason: String? = nil,
                prefillMs: Int? = nil, generationMs: Int? = nil) {
        self.index = index
        self.text = text
        self.state = state
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.latencyMs = latencyMs
        self.attempts = attempts
        self.reason = reason
        self.prefillMs = prefillMs
        self.generationMs = generationMs
    }
}

public struct CleanupOutcome: Sendable, Equatable {
    public var text: String
    public var state: CleanupState
    public var chunks: [ChunkOutcome]
    public var diagnostics: [Diagnostic]
    public init(text: String, state: CleanupState, chunks: [ChunkOutcome], diagnostics: [Diagnostic]) {
        self.text = text
        self.state = state
        self.chunks = chunks
        self.diagnostics = diagnostics
    }
}

/// Collapses an exactly repeated path segment emitted twice by the model
/// (`lib/backend/backend/main` -> `lib/backend/main`). Only an identical
/// adjacent segment is removed; a real `foo/foo` path in the source is rare and
/// the protected-literal guard still compares the repaired path to the input.
enum RepeatedPathSegment {
    private static let pattern = try? NSRegularExpression(
        pattern: #"(?i)/([A-Za-z0-9_.-]+)/\1(?=/|[^A-Za-z0-9_.-]|$)"#)

    static func collapse(_ text: String) -> String {
        guard let pattern else { return text }
        var out = text
        for _ in 0..<4 {
            let ns = out as NSString
            let ranges = pattern.matches(in: out, range: NSRange(location: 0, length: ns.length))
            guard !ranges.isEmpty else { break }
            var rebuilt = ""
            var cursor = 0
            for match in ranges where match.range.location >= cursor {
                rebuilt += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                rebuilt += "/" + ns.substring(with: match.range(at: 1))
                cursor = NSMaxRange(match.range)
            }
            rebuilt += ns.substring(from: cursor)
            guard rebuilt != out else { break }
            out = rebuilt
        }
        return out
    }
}

/// Decorates the unchanged TextCleaner port with deterministic planning and fallback.
public actor CleanupService {
    let cleaner: any TextCleaner
    private let metrics: any MetricsSink
    public let config: CleanupConfig
    let structureMapping: any StructureMapping

    /// One global inference budget shared by every cleanup call. The llama.cpp
    /// runtime exposes a fixed pool of sessions (LlamaCppRuntime.maximumSessions);
    /// every model call — each worker and each of its internal sub-chunk lanes —
    /// takes one permit. `workers x lanes` therefore can never exceed the
    /// sessions actually available, no matter how many cleanups are in flight.
    private static let sessionBudget = 10
    static let inferenceSemaphore = AsyncSemaphore(sessionBudget)

    public init(cleaner: any TextCleaner, config: CleanupConfig = CleanupConfig(),
                metrics: any MetricsSink = NoopMetrics(),
                structureMapping: any StructureMapping = S1MiniStructureMapping()) {
        self.cleaner = cleaner
        self.metrics = metrics
        var bounded = config
        bounded.hardTokenCap = min(CleanupConfig.maximumInputTokens, max(1, config.hardTokenCap))
        bounded.workers = min(10, max(1, config.workers))
        self.config = bounded
        self.structureMapping = structureMapping
    }

    public func countTokens(_ text: String) async -> Int { await cleaner.countTokens(text) }

    public func clean(_ input: String, protected: Protected = Protected(), context: TextContext) async -> CleanupOutcome {
        let tier0 = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tier0.isEmpty else { return CleanupOutcome(text: "", state: .skipped, chunks: [], diagnostics: []) }
        guard context.settings.cleanupEnabled else {
            return CleanupOutcome(text: tier0, state: .skipped, chunks: [], diagnostics: [])
        }
        guard await cleaner.isReady else {
            metrics.event("cleanup.chunk.helper_unavailable", [:])
            return CleanupOutcome(text: tier0, state: .fallback, chunks: [],
                                  diagnostics: [Diagnostic(stage: "cleanup", message: "model not ready")])
        }
        return await CleanPriority.$current.withValue(context.interactive ? .interactive : .background) {
            let output = await self.prose(tier0, protected: protected, context: context,
                                          styling: context.settings.cleanupStyling,
                                          structure: context.settings.cleanupStructure)
            for chunk in output.chunks {
                let outcome = self.outcomeTag(chunk)
                var fields = ["tokensIn": String(chunk.tokensIn), "tokensOut": String(chunk.tokensOut),
                              "latencyMs": String(chunk.latencyMs), "attempts": String(chunk.attempts)]
                if let ms = chunk.prefillMs { fields["prefillMs"] = String(ms) }
                if let ms = chunk.generationMs { fields["generationMs"] = String(ms) }
                self.metrics.event("cleanup.chunk." + outcome, fields)
                self.metrics.record("cleanup.chunk.ms", valueMs: Double(chunk.latencyMs))
            }
            let fallback = output.chunks.contains { $0.state == .fallback }
            return CleanupOutcome(text: output.text, state: fallback ? .fallback : .cleaned,
                                  chunks: output.chunks, diagnostics: output.chunks.compactMap { chunk in
                chunk.reason.map { Diagnostic(stage: "cleanup[\(chunk.index)]", message: $0) }
            })
        }
    }

    private func outcomeTag(_ chunk: ChunkOutcome) -> String {
        guard chunk.state == .fallback else { return "accepted" }
        let reason = chunk.reason ?? ""
        if ["truncated", "protectedLost", "contentChanged", "empty", "quoteChanged"].contains(reason) { return "rejected." + reason }
        if reason.localizedCaseInsensitiveContains("timeout") || reason.localizedCaseInsensitiveContains("timed out") { return "deadline" }
        if reason.localizedCaseInsensitiveContains("cancel") { return "cancelled" }
        return "runtime_error"
    }

    private func prose(_ text: String, protected: Protected, context: TextContext,
                       styling: String, structure: String) async -> (text: String, chunks: [ChunkOutcome]) {
        let count = await cleaner.countTokens(text)
        var plans: [ChunkPlan]
        if count <= min(config.softTokenTarget, config.hardTokenCap) {
            plans = [ChunkPlan(index: 0, text: text, tokens: count)]
        } else {
            let words = WordTimingProjection.apply(to: Tokenizer.words(text, protected: protected), timings: context.wordTimings)
            // Keep the configured seam overlap. Each plan re-shares the previous
            // chunk's trailing sentences as context; `assemble` removes them
            // again with the real splicer alignment after cleanup.
            plans = await ChunkPlanner(config: config, protected: protected).plan(words) { await self.cleaner.countTokens($0) }
        }
        plans = await coalesceChunks(plans, protected: protected)
        guard !plans.isEmpty else { return ("", []) }
        var results = [ChunkOutcome](repeating: ChunkOutcome(index: 0, text: "", state: .pending), count: plans.count)
        // Size the lane pool from the same soft target the planner used. The
        // old hard-coded 800 under-counted lanes whenever the target was 600,
        // leaving model sessions idle. `config.workers` and the global session
        // semaphore still bound the pool, so a transcript never opens more
        // model calls than there are llama contexts — no oversubscription.
        let chunkTarget = min(config.hardTokenCap, max(1, config.softTokenTarget))
        let totalTokens = plans.reduce(0) { $0 + $1.tokens }
        let neededChunks = max(1, (totalTokens + chunkTarget - 1) / chunkTarget)
        let workerCount = min(config.workers, plans.count, Self.sessionBudget, max(2, neededChunks))
        await withTaskGroup(of: ChunkOutcome.self) { group in
            var next = 0
            for _ in 0..<workerCount {
                let plan = plans[next]; next += 1
                group.addTask { await self.cleanPlan(plan, styling: styling, structure: structure, protected: protected, context: context) }
            }
            for await result in group {
                results[result.index] = result
                if next < plans.count {
                    let plan = plans[next]; next += 1
                    group.addTask { await self.cleanPlan(plan, styling: styling, structure: structure, protected: protected, context: context) }
                }
            }
        }
        return (assemble(results.map(\.text)), results)
    }

    /// Re-assembles cleaned chunk texts, removing the planner's repeated seam
    /// context with the splicer's real alignment (not a plain join). Overlap is
    /// estimated from the same soft-target fraction the planner uses.
    private func assemble(_ parts: [String]) -> String {
        let overlapWords = Int(Double(config.softTokenTarget) * min(0.20, max(0, config.overlapPercent)))
        guard var out = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else {
            return SeamSplicer.join(parts)
        }
        for raw in parts.dropFirst() {
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            let splice = SeamSplicer.splice(out, piece, overlapWords: overlapWords)
            let kept = splice.kept.trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = splice.rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.isEmpty { out = kept; continue }
            out = kept.isEmpty ? rest : kept + " " + rest
        }
        return out
    }

    /// Merge adjacent small chunks so a long transcript spends fewer model
    /// calls. A pair is merged when its combined model input fits the soft
    /// target (the hard cap for a list run that must stay whole), no protected
    /// literal or email address sits on the seam, and the merge cannot strand
    /// a list straddle with the following chunk. Overlap is preserved so the
    /// seam splicer still sees the next chunk's leading context.
    func coalesceChunks(_ plans: [ChunkPlan], protected: Protected) async -> [ChunkPlan] {
        guard plans.count > 1 else { return plans }
        let target = min(config.hardTokenCap, max(1, config.softTokenTarget))
        var merged: [ChunkPlan] = []
        merged.reserveCapacity(plans.count)
        var current = plans[0]
        var index = 1
        while index < plans.count {
            let next = plans[index]
            let lookahead = index + 1 < plans.count ? plans[index + 1] : nil
            if let combined = await merge(current, next, target: target, lookahead: lookahead, protected: protected) {
                current = combined
            } else {
                merged.append(current)
                current = next
            }
            index += 1
        }
        merged.append(current)
        return merged.enumerated().map { offset, plan in
            ChunkPlan(index: offset, text: plan.text, tokens: plan.tokens,
                      overlap: plan.overlap, ownedText: plan.ownedText)
        }
    }

    private func merge(_ left: ChunkPlan, _ right: ChunkPlan, target: Int,
                       lookahead: ChunkPlan?, protected: Protected) async -> ChunkPlan? {
        let straddlesList = EnumerationDetector.straddles(left.ownedText, right.ownedText)
        let budget = straddlesList ? config.hardTokenCap : target
        guard !Self.hasProtectedSeam(left.ownedText, right.ownedText, protected: protected) else { return nil }
        let owned = left.ownedText + " " + right.ownedText
        let text = left.text + " " + right.ownedText
        let tokens = await cleaner.countTokens(text)
        guard tokens <= budget else { return nil }
        // Look ahead: if the merge would create a list straddle with the next
        // chunk that can no longer fit under the cap, leave this seam intact.
        if let next = lookahead, EnumerationDetector.straddles(owned, next.ownedText) {
            let withNext = await cleaner.countTokens(text + " " + next.ownedText)
            guard withNext <= config.hardTokenCap else { return nil }
        }
        return ChunkPlan(index: left.index, text: text, tokens: tokens,
                         overlap: left.overlap, ownedText: owned)
    }

    /// A protected literal or email address must never be the boundary that a
    /// coalescing pass crosses. Both are whole tokens on the planner's word
    /// grid, so checking the two words adjacent to the seam is sufficient.
    private static func hasProtectedSeam(_ left: String, _ right: String,
                                         protected: Protected) -> Bool {
        guard let last = Tokenizer.words(in: left).last,
              let first = Tokenizer.words(in: right).first else { return false }
        func sensitive(_ word: String) -> Bool {
            word.contains("@") || !protected.ranges(in: word, detect: false).isEmpty
        }
        return sensitive(last) || sensitive(first)
    }

}

public struct CleanupStage: SuperflowPorts.TextStage {
    public let id = "cleanup"
    private let service: CleanupService
    public init(service: CleanupService) { self.service = service }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit, !(draft.text.isEmpty && draft.cleanupState == .cleaned) else { return draft }
        let outcome = await service.clean(draft.text, protected: draft.protected, context: context)
        var output = draft
        output.text = outcome.text
        output.cleanupState = outcome.state
        output.diagnostics.append(contentsOf: outcome.diagnostics)
        return output
    }
}
