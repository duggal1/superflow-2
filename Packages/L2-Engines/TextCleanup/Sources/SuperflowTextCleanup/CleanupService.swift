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

/// Decorates the unchanged TextCleaner port with deterministic planning and fallback.
public actor CleanupService {
    private let cleaner: any TextCleaner
    private let metrics: any MetricsSink
    public let config: CleanupConfig
    private let semaphore: AsyncSemaphore
    private let structureMapping: any StructureMapping

    public init(cleaner: any TextCleaner, config: CleanupConfig = CleanupConfig(),
                metrics: any MetricsSink = NoopMetrics(),
                structureMapping: any StructureMapping = S1MiniStructureMapping()) {
        self.cleaner = cleaner
        self.metrics = metrics
        var bounded = config
        bounded.hardTokenCap = min(CleanupConfig.maximumInputTokens, max(1, config.hardTokenCap))
        bounded.workers = min(2, max(1, config.workers))
        self.config = bounded
        self.semaphore = AsyncSemaphore(bounded.workers)
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
            var planning = config
            planning.overlapPercent = 0
            plans = await ChunkPlanner(config: planning, protected: protected).plan(words) { await self.cleaner.countTokens($0) }
        }
        plans = await coalesceEnumerationSeams(plans)
        guard !plans.isEmpty else { return ("", []) }
        var results = [ChunkOutcome](repeating: ChunkOutcome(index: 0, text: "", state: .pending), count: plans.count)
        await withTaskGroup(of: ChunkOutcome.self) { group in
            var next = 0
            for _ in 0..<min(config.workers, plans.count) {
                let plan = plans[next]; next += 1
                group.addTask { await self.cleanChunk(plan, styling: styling, structure: structure, protected: protected, context: context) }
            }
            for await result in group {
                results[result.index] = result
                if next < plans.count {
                    let plan = plans[next]; next += 1
                    group.addTask { await self.cleanChunk(plan, styling: styling, structure: structure, protected: protected, context: context) }
                }
            }
        }
        return (SeamSplicer.join(results.map(\.text)), results)
    }

    /// A spoken list must reach the model in one request. When an ordered run
    /// straddles a cut, merge the two chunks if the merged input still fits.
    private func coalesceEnumerationSeams(_ plans: [ChunkPlan]) async -> [ChunkPlan] {
        guard plans.count > 1 else { return plans }
        var merged: [ChunkPlan] = []
        var index = 0
        while index < plans.count {
            let current = plans[index]
            if index + 1 < plans.count,
               EnumerationDetector.straddles(current.text, plans[index + 1].text) {
                let combined = current.ownedText + " " + plans[index + 1].ownedText
                let tokens = await cleaner.countTokens(combined)
                if tokens <= config.hardTokenCap {
                    merged.append(ChunkPlan(index: 0, text: combined, tokens: tokens))
                    index += 2
                    continue
                }
            }
            merged.append(current)
            index += 1
        }
        return merged.enumerated().map { offset, plan in
            ChunkPlan(index: offset, text: plan.text, tokens: plan.tokens,
                      overlap: plan.overlap, ownedText: plan.ownedText)
        }
    }

    private func cleanChunk(_ plan: ChunkPlan, styling: String, structure: String,
                            protected: Protected, context: TextContext) async -> ChunkOutcome {
        if plan.tokens > config.hardTokenCap {
            return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback,
                                reason: "protected span exceeds input cap")
        }
        let start = ContinuousClock.now
        let configured = context.interactive ? context.settings.interactiveDeadlineMs : context.settings.backgroundDeadlineMs
        let ceiling = context.interactive ? config.interactiveDeadlineMs : config.backgroundDeadlineMs
        let deadline = min(max(1, configured), max(1, ceiling))
        let measuredTokens: Int
        if plan.tokens > 0 { measuredTokens = plan.tokens }
        else { measuredTokens = await cleaner.countTokens(plan.text) }
        let cap = min(config.maxNewTokens, Int(1.3 * Double(measuredTokens)) + 32)
        var tokensIn = 0
        var tokensOut = 0
        var prefillMs: Int?
        var generationMs: Int?
        do {
            try Task.checkCancellation()
            let baseStructure = CleanupStructureDetector.structure(for: plan.text, configured: structure)
            let detectedStructure = structureMapping.structure(
                for: EnumerationDetector.detect(plan.text), base: baseStructure)
            let canQuote = config.format.spokenQuotes
                && protected.ranges(in: plan.text, detect: false).isEmpty
            let modelInput = canQuote
                ? SpokenQuotes.apply(plan.text, style: config.format.quoteStyle)
                : plan.text
            try await semaphore.acquire(priority: CleanPriority.current)
            let result: CleanResult
            do {
                let options = CleanOptions(styling: styling, structure: detectedStructure, context: context.cleanupContext,
                                           deadlineMs: deadline, maxNewTokens: cap)
                if cleaner is any DeadlineManagedTextCleaner {
                    result = try await cleaner.clean(modelInput, options: options)
                } else {
                    result = try await withDeadline(ms: deadline) { try await self.cleaner.clean(modelInput, options: options) }
                }
                await semaphore.release()
            } catch { await semaphore.release(); throw error }
            tokensIn = result.tokensIn
            tokensOut = result.tokensOut
            prefillMs = result.prefillMs
            generationMs = result.generationMs
            if let failure = CleanGuard.verify(input: modelInput, protected: protected, result: result, cap: cap) { throw failure }
            if canQuote, !QuoteGate.preserved(input: modelInput, output: result.text) {
                throw CleanGuard.Failure.quoteChanged
            }
            let elapsed = start.duration(to: .now)
            return ChunkOutcome(index: plan.index, text: result.text, state: .cleaned, tokensIn: result.tokensIn,
                                tokensOut: result.tokensOut, latencyMs: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000), attempts: 1, prefillMs: result.prefillMs, generationMs: result.generationMs)
        } catch {
            let elapsed = start.duration(to: .now)
            return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback,
                                tokensIn: tokensIn, tokensOut: tokensOut,
                                latencyMs: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000),
                                attempts: 1, reason: String(describing: error), prefillMs: prefillMs, generationMs: generationMs)
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
