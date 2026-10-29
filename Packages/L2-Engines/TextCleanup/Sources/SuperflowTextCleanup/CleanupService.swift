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
    public var reason: String?
    public init(index: Int, text: String, state: CleanupState, tokensIn: Int = 0, tokensOut: Int = 0,
                latencyMs: Int = 0, attempts: Int = 0, reason: String? = nil) {
        self.index = index
        self.text = text
        self.state = state
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.latencyMs = latencyMs
        self.attempts = attempts
        self.reason = reason
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

/// Decorates the unchanged TextCleaner port with deterministic planning and fallback.
public actor CleanupService {
    private let cleaner: any TextCleaner
    public let config: CleanupConfig
    private let semaphore: AsyncSemaphore

    public init(cleaner: any TextCleaner, config: CleanupConfig = CleanupConfig()) {
        self.cleaner = cleaner
        self.config = config
        self.semaphore = AsyncSemaphore(config.workers)
    }

    public func countTokens(_ text: String) async -> Int { await cleaner.countTokens(text) }

    public func clean(_ input: String, protected: Protected = Protected(), context: TextContext) async -> CleanupOutcome {
        let tier0 = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tier0.isEmpty else { return CleanupOutcome(text: "", state: .skipped, chunks: [], diagnostics: []) }
        guard context.settings.cleanupEnabled else {
            return CleanupOutcome(text: tier0, state: .skipped, chunks: [], diagnostics: [])
        }
        guard await cleaner.isReady else {
            return CleanupOutcome(text: tier0, state: .fallback, chunks: [],
                                  diagnostics: [Diagnostic(stage: "cleanup", message: "model not ready")])
        }
        return await CleanPriority.$current.withValue(context.interactive ? .interactive : .background) {
            var parts: [String] = []
            var chunks: [ChunkOutcome] = []
            for segment in ListPlanner.plan(tier0, protected: protected, timings: context.wordTimings) {
                switch segment {
                case .prose(let text):
                    let output = await self.prose(text, protected: protected, context: context,
                                                  styling: context.settings.cleanupStyling,
                                                  structure: context.settings.cleanupStructure)
                    parts.append(output.text); chunks.append(contentsOf: output.chunks)
                case .list(let lead, let items):
                    let heading = await self.prose(lead, protected: protected, context: context,
                                                   styling: context.settings.cleanupStyling, structure: "prose")
                    chunks.append(contentsOf: heading.chunks)
                    var cleaned: [String] = []
                    for item in items {
                        let output = await self.prose(item, protected: protected, context: context,
                                                      styling: "semi-casual", structure: "prose")
                        cleaned.append(output.text); chunks.append(contentsOf: output.chunks)
                    }
                    parts.append(ListRenderer.render(lead: heading.text, items: cleaned, protected: protected))
                }
            }
            for index in chunks.indices { chunks[index].index = index }
            let fallback = chunks.contains { $0.state == .fallback }
            return CleanupOutcome(text: parts.filter { !$0.isEmpty }.joined(separator: "\n\n"),
                                  state: fallback ? .fallback : .cleaned, chunks: chunks,
                                  diagnostics: chunks.compactMap { chunk in
                chunk.reason.map { Diagnostic(stage: "cleanup[\(chunk.index)]", message: $0) }
            })
        }
    }

    private func prose(_ text: String, protected: Protected, context: TextContext,
                       styling: String, structure: String) async -> (text: String, chunks: [ChunkOutcome]) {
        let words = WordTimingProjection.apply(to: Tokenizer.words(text, protected: protected), timings: context.wordTimings)
        let plans = await ChunkPlanner(config: config, protected: protected).plan(words) { await self.cleaner.countTokens($0) }
        guard !plans.isEmpty else { return ("", []) }
        var results = [ChunkOutcome](repeating: ChunkOutcome(index: 0, text: "", state: .pending), count: plans.count)
        await withTaskGroup(of: ChunkOutcome.self) { group in
            var next = 0
            for _ in 0..<min(config.workers, plans.count) {
                let plan = plans[next]; next += 1
                group.addTask { await self.cleanChunk(plan, depth: 0, styling: styling, structure: structure, protected: protected, context: context) }
            }
            for await result in group {
                results[result.index] = result
                if next < plans.count {
                    let plan = plans[next]; next += 1
                    group.addTask { await self.cleanChunk(plan, depth: 0, styling: styling, structure: structure, protected: protected, context: context) }
                }
            }
        }
        var pieces: [String] = []
        var tail = results[0].text
        for index in plans.indices.dropFirst() {
            if !plans[index].overlap.isEmpty {
                let splice = SeamSplicer.splice(tail, results[index].text, overlapWords: wordCount(plans[index].overlap))
                if splice.aligned { pieces.append(splice.kept); tail = splice.rest; continue }
                pieces.append(tail)
                let owned = ChunkPlan(index: index, text: plans[index].ownedText, tokens: 0)
                let replacement = await cleanChunk(owned, depth: 0, styling: styling, structure: structure, protected: protected, context: context)
                results[index] = replacement; tail = replacement.text
            } else { pieces.append(tail); tail = results[index].text }
        }
        pieces.append(tail)
        let assembled = SeamSplicer.join(pieces)
        let check = CleanResult(text: assembled, tokensIn: 0, tokensOut: 0, hitTokenCap: false, latencyMs: 0)
        if CleanGuard.verify(input: text, protected: protected, result: check, cap: Int.max) != nil {
            for index in results.indices {
                results[index].text = plans[index].ownedText
                results[index].state = .fallback
                results[index].reason = "assembly content guard"
            }
            return (text, results)
        }
        return (assembled, results)
    }

    private func cleanChunk(_ plan: ChunkPlan, depth: Int, styling: String, structure: String,
                            protected: Protected, context: TextContext) async -> ChunkOutcome {
        if plan.tokens > config.hardTokenCap {
            return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback,
                                reason: "protected span exceeds input cap")
        }
        let start = ContinuousClock.now
        let configured = context.interactive ? context.settings.interactiveDeadlineMs : context.settings.backgroundDeadlineMs
        let ceiling = context.interactive ? config.interactiveDeadlineMs : config.backgroundDeadlineMs
        let deadline = min(max(1, configured), max(1, ceiling))
        let cap = min(config.maxNewTokens, Int(1.3 * Double(await cleaner.countTokens(plan.text))) + 32)
        var tokensIn = 0
        var tokensOut = 0
        do {
            try Task.checkCancellation()
            try await semaphore.acquire(priority: CleanPriority.current)
            let result: CleanResult
            do {
                let options = CleanOptions(styling: styling, structure: structure, context: context.cleanupContext,
                                           deadlineMs: deadline, maxNewTokens: cap)
                if cleaner is any DeadlineManagedTextCleaner {
                    result = try await cleaner.clean(plan.text, options: options)
                } else {
                    result = try await withDeadline(ms: deadline) { try await self.cleaner.clean(plan.text, options: options) }
                }
                await semaphore.release()
            } catch { await semaphore.release(); throw error }
            tokensIn = result.tokensIn
            tokensOut = result.tokensOut
            if let failure = CleanGuard.verify(input: plan.text, protected: protected, result: result, cap: cap) { throw failure }
            let elapsed = start.duration(to: .now)
            return ChunkOutcome(index: plan.index, text: result.text, state: .cleaned, tokensIn: result.tokensIn,
                                tokensOut: result.tokensOut, latencyMs: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000), attempts: depth + 1)
        } catch {
            if depth < config.retryDepth, !(error is CancellationError), !Task.isCancelled {
                let words = Tokenizer.tokens(in: plan.text)
                if words.count >= 48 {
                    let spans = protected.ranges(in: plan.text)
                    let middle = words.count / 2
                    if let cut = (1..<words.count).sorted(by: { abs($0 - middle) < abs($1 - middle) }).first(where: { index in
                        !spans.contains { $0.lowerBound < words[index].range.lowerBound && words[index].range.lowerBound < $0.upperBound }
                    }) {
                        let lhs = words[..<cut].map(\.full).joined(separator: " ")
                        let rhs = words[cut...].map(\.full).joined(separator: " ")
                        let a = await cleanChunk(ChunkPlan(index: plan.index, text: lhs, tokens: 0), depth: depth + 1,
                                                 styling: styling, structure: structure, protected: protected, context: context)
                        let b = await cleanChunk(ChunkPlan(index: plan.index, text: rhs, tokens: 0), depth: depth + 1,
                                                 styling: styling, structure: structure, protected: protected, context: context)
                        return ChunkOutcome(index: plan.index, text: SeamSplicer.join([a.text, b.text]),
                                            state: a.state == .cleaned && b.state == .cleaned ? .cleaned : .fallback,
                                            tokensIn: tokensIn + a.tokensIn + b.tokensIn, tokensOut: tokensOut + a.tokensOut + b.tokensOut,
                                            latencyMs: a.latencyMs + b.latencyMs, attempts: a.attempts + b.attempts,
                                            reason: String(describing: error))
                    }
                }
            }
            let elapsed = start.duration(to: .now)
            return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback,
                                tokensIn: tokensIn, tokensOut: tokensOut,
                                latencyMs: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000),
                                attempts: depth + 1, reason: String(describing: error))
        }
    }

    private func withDeadline<T: Sendable>(ms: Int, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .milliseconds(ms))
                throw SuperflowError.timeout("cleanup")
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw SuperflowError.timeout("cleanup") }
            return first
        }
    }
}

public struct CleanupStage: TextStage {
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
