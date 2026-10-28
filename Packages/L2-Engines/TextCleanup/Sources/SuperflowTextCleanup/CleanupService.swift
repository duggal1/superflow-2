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

/// Bounded, cancellable cleanup over ordered chunks. Every failure path returns the Tier 0 text.
public actor CleanupService {
    private let cleaner: any TextCleaner
    public let config: CleanupConfig
    private let semaphore: AsyncSemaphore
    private let truncation: TruncationDetector
    private let guardrail: HallucinationGuard

    public init(cleaner: any TextCleaner, config: CleanupConfig = CleanupConfig()) {
        self.cleaner = cleaner
        self.config = config
        self.semaphore = AsyncSemaphore(config.workers)
        self.truncation = TruncationDetector(ratioFloor: config.ratioFloor)
        self.guardrail = HallucinationGuard()
    }

    public func countTokens(_ text: String) async -> Int {
        await cleaner.countTokens(text)
    }

    public func clean(_ input: String, protected: Protected = Protected(),
                      context: TextContext) async -> CleanupOutcome {
        let tier0 = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tier0.isEmpty else {
            return CleanupOutcome(text: "", state: .skipped, chunks: [], diagnostics: [])
        }
        guard context.settings.cleanupEnabled else {
            return CleanupOutcome(text: tier0, state: .skipped, chunks: [],
                                  diagnostics: [Diagnostic(stage: "cleanup", message: "disabled")])
        }
        guard await cleaner.isReady else {
            return CleanupOutcome(text: tier0, state: .fallback, chunks: [],
                                  diagnostics: [Diagnostic(stage: "cleanup", message: "model not ready")])
        }

        let configured = context.interactive ? context.settings.interactiveDeadlineMs : context.settings.backgroundDeadlineMs
        let ceiling = context.interactive ? config.interactiveDeadlineMs : config.backgroundDeadlineMs
        let deadline = min(max(1, configured), max(1, ceiling))
        let planner = ChunkPlanner(config: config, protected: protected)
        let plans = await planner.plan(tier0) { await self.cleaner.countTokens($0) }
        guard !plans.isEmpty else {
            return CleanupOutcome(text: tier0, state: .fallback, chunks: [], diagnostics: [])
        }

        var outcomes: [ChunkOutcome] = Array(repeating: ChunkOutcome(index: 0, text: "", state: .pending),
                                             count: plans.count)
        await withTaskGroup(of: ChunkOutcome.self) { group in
            for plan in plans {
                group.addTask { [weak self] in
                    guard let self else {
                        return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback)
                    }
                    await self.semaphore.acquire()
                    let result = await self.cleanChunk(plan, deadlineMs: deadline, depth: 0,
                                                       protected: protected, context: context)
                    await self.semaphore.release()
                    return result
                }
            }
            for await result in group { outcomes[result.index] = result }
        }

        let stitched = SeamRepair.stitch(outcomes.map(\.text))
        let anyFallback = outcomes.contains { $0.state == .fallback }
        let anyCleaned = outcomes.contains { $0.state == .cleaned }
        let state: CleanupState = anyFallback ? .fallback : (anyCleaned ? .cleaned : .skipped)
        let diagnostics = outcomes.compactMap { outcome in
            outcome.reason.map { Diagnostic(stage: "cleanup[\(outcome.index)]", message: $0) }
        }
        // A successful cleanup may legitimately be empty (filler-only input).
        // Only an empty fallback needs the Tier 0 text restored.
        let text = stitched.isEmpty && state != .cleaned ? tier0 : stitched
        return CleanupOutcome(text: text, state: state, chunks: outcomes, diagnostics: diagnostics)
    }

    private func cleanChunk(_ plan: ChunkPlan, deadlineMs: Int, depth: Int,
                            protected: Protected, context: TextContext) async -> ChunkOutcome {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try await withDeadline(ms: deadlineMs) {
                try await self.cleaner.clean(plan.text, options: CleanOptions(
                    styling: context.settings.cleanupStyling,
                    structure: CleanupStructureDetector.structure(
                        for: plan.text, configured: context.settings.cleanupStructure),
                    context: context.cleanupContext,
                    deadlineMs: deadlineMs,
                    maxNewTokens: self.config.maxNewTokens))
            }
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)

            let emptyOutput = result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if emptyOutput, FillerOnlyText.isFillerOnly(plan.text) {
                return ChunkOutcome(index: plan.index, text: "", state: .cleaned,
                                    tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                                    latencyMs: elapsed, attempts: depth + 1)
            }

            if let reason = truncation.detect(input: plan.text, output: result.text, hitTokenCap: result.hitTokenCap),
               depth < config.retryDepth {
                let halves = splitForRetry(plan.text, protected: protected)
                if halves.count == 2 {
                    let a = await cleanChunk(ChunkPlan(index: plan.index, text: halves[0], tokens: 0),
                                             deadlineMs: deadlineMs, depth: depth + 1,
                                             protected: protected, context: context)
                    let b = await cleanChunk(ChunkPlan(index: plan.index, text: halves[1], tokens: 0),
                                             deadlineMs: deadlineMs, depth: depth + 1,
                                             protected: protected, context: context)
                    let text = SeamRepair.stitch([a.text, b.text])
                    let state: CleanupState = (a.state == .cleaned && b.state == .cleaned) ? .cleaned : .fallback
                    return ChunkOutcome(index: plan.index, text: text, state: state,
                                        tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                                        latencyMs: elapsed, attempts: a.attempts + b.attempts + 1, reason: reason.rawValue)
                }
            }

            if let reason = truncation.detect(input: plan.text, output: result.text, hitTokenCap: result.hitTokenCap) {
                return fallback(plan, reason: reason.rawValue, elapsed: elapsed)
            }
            if !guardrail.allows(input: plan.text, output: result.text) {
                return fallback(plan, reason: "hallucination guard", elapsed: elapsed)
            }
            return ChunkOutcome(index: plan.index, text: result.text, state: .cleaned,
                                tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                                latencyMs: elapsed, attempts: depth + 1)
        } catch {
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            if depth < config.retryDepth, !(error is CancellationError) {
                let halves = splitForRetry(plan.text, protected: protected)
                if halves.count == 2 {
                    let a = await cleanChunk(ChunkPlan(index: plan.index, text: halves[0], tokens: 0),
                                             deadlineMs: deadlineMs, depth: depth + 1,
                                             protected: protected, context: context)
                    let b = await cleanChunk(ChunkPlan(index: plan.index, text: halves[1], tokens: 0),
                                             deadlineMs: deadlineMs, depth: depth + 1,
                                             protected: protected, context: context)
                    let state: CleanupState = (a.state == .cleaned && b.state == .cleaned) ? .cleaned : .fallback
                    return ChunkOutcome(index: plan.index, text: SeamRepair.stitch([a.text, b.text]), state: state,
                                        latencyMs: elapsed, attempts: a.attempts + b.attempts + 1,
                                        reason: String(describing: error))
                }
            }
            return fallback(plan, reason: String(describing: error), elapsed: elapsed)
        }
    }

    private func fallback(_ plan: ChunkPlan, reason: String, elapsed: Int) -> ChunkOutcome {
        ChunkOutcome(index: plan.index, text: plan.text, state: .fallback, latencyMs: elapsed, reason: reason)
    }

    private func splitForRetry(_ text: String, protected: Protected) -> [String] {
        let (sentences, remainder) = SentenceSplitter.split(text)
        if sentences.count >= 2 {
            let mid = sentences.count / 2
            let a = sentences[0..<mid].joined(separator: " ")
            let b = sentences[mid...].joined(separator: " ") + (remainder.isEmpty ? "" : " " + remainder)
            if !a.isEmpty && !b.isEmpty { return [a, b] }
        }
        let tokens = Tokenizer.tokens(in: text)
        guard tokens.count > 4 else { return [] }
        let mid = tokens.count / 2
        var index = mid
        if index > 0, index < tokens.count,
           protected.overlaps(tokens[index].range, in: text, detect: false) {
            index = min(tokens.count - 1, index + 1)
        }
        let a = tokens[0..<index].map(\.full).joined(separator: " ")
        let b = tokens[index...].map(\.full).joined(separator: " ")
        return a.isEmpty || b.isEmpty ? [] : [a, b]
    }

    private func withDeadline<T: Sendable>(ms: Int, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .milliseconds(max(1, ms)))
                throw SuperflowError.timeout("cleanup")
            }
            guard let first = try await group.next() else { throw SuperflowError.timeout("cleanup") }
            group.cancelAll()
            return first
        }
    }
}

public struct CleanupStage: TextStage {
    public let id = "cleanup"
    private let service: CleanupService
    public init(service: CleanupService) { self.service = service }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        let outcome = await service.clean(draft.text, protected: draft.protected, context: context)
        var output = draft
        output.text = outcome.text
        output.cleanupState = outcome.state
        output.diagnostics.append(contentsOf: outcome.diagnostics)
        return output
    }
}
