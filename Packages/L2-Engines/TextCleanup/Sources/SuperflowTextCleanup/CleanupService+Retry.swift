import Foundation
import SuperflowKernel
import SuperflowPorts

extension CleanupService {
    /// Result of one model request plus guard check. `failure == nil` is success.
    private struct Attempt: Sendable {
        var text = ""
        var tokensIn = 0
        var tokensOut = 0
        var latencyMs = 0
        var prefillMs: Int?
        var generationMs: Int?
        var failure: String?
    }

    /// One model request and its guard checks. Failures are returned as data so
    /// `cleanChunk` can split-and-retry without losing the timing/metric fields.
    private func attempt(_ plan: ChunkPlan, styling: String, structure: String,
                         protected: Protected, context: TextContext) async -> Attempt {
        if plan.tokens > config.hardTokenCap {
            return Attempt(failure: "protected span exceeds input cap")
        }
        let start = ContinuousClock.now
        let configured = context.interactive ? context.settings.interactiveDeadlineMs : context.settings.backgroundDeadlineMs
        let ceiling = context.interactive ? config.interactiveDeadlineMs : config.backgroundDeadlineMs
        let base = min(max(1, configured), max(1, ceiling))
        // A 1.5 s budget is right for a short utterance, but a 150-token
        // engineering transcript needs longer to decode than a 20-token one.
        // Scale only the excess over a short baseline and never exceed the
        // background ceiling, so short dictation keeps its fast fallback.
        let scaled = context.interactive ? base + max(0, plan.tokens - 60) * 12 : base
        let deadline = min(scaled, max(1, config.backgroundDeadlineMs))
        let measuredTokens: Int
        if plan.tokens > 0 { measuredTokens = plan.tokens }
        else { measuredTokens = await cleaner.countTokens(plan.text) }
        let cap = min(config.maxNewTokens, Int(1.3 * Double(measuredTokens)) + 32)
        do {
            try Task.checkCancellation()
            let baseStructure = CleanupStructureDetector.structure(for: plan.text, configured: structure)
            let detectedStructure = structureMapping.structure(
                for: EnumerationDetector.detect(plan.text), base: baseStructure)
            let canQuote = (config.format.spokenQuotes || context.settings.commandsEnabled)
                && plan.text.localizedCaseInsensitiveContains("quote")
                && protected.ranges(in: plan.text, detect: false).isEmpty
            let modelInput = canQuote
                ? SpokenQuotes.apply(plan.text, style: config.format.quoteStyle)
                : plan.text
            // Acquire from the single global budget before starting the deadline.
            // Queue wait therefore never consumes the model's generation time.
            try await Self.inferenceSemaphore.acquire(priority: CleanPriority.current)
            let result: CleanResult
            do {
                let options = CleanOptions(styling: styling, structure: detectedStructure, context: context.cleanupContext,
                                           deadlineMs: deadline, maxNewTokens: cap)
                if cleaner is any DeadlineManagedTextCleaner {
                    result = try await cleaner.clean(modelInput, options: options)
                } else {
                    result = try await withDeadline(ms: deadline) { try await self.cleaner.clean(modelInput, options: options) }
                }
                await Self.inferenceSemaphore.release()
            } catch { await Self.inferenceSemaphore.release(); throw error }
            // S1-mini sometimes repeats a path segment it just emitted
            // ("lib/backend/backend/main/..."). Collapse that exact stutter so
            // a single mechanical slip does not discard an otherwise correct
            // cleanup and force the much weaker Tier-0 fallback.
            let collapsed = RepeatedPathSegment.collapse(result.text)
            let repairedText = modelInput == plan.text ? collapsed
                : QuoteGate.restoreDictatedContents(input: modelInput, output: collapsed)
            let checked = CleanResult(text: repairedText, tokensIn: result.tokensIn,
                                      tokensOut: result.tokensOut, hitTokenCap: result.hitTokenCap,
                                      latencyMs: result.latencyMs, prefillMs: result.prefillMs, generationMs: result.generationMs)
            if let failure = CleanGuard.verify(input: modelInput, protected: protected, result: checked, cap: cap) {
                #if DEBUG
                if ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_DEBUG"] == "1" {
                    FileHandle.standardError.write(Data("CLEANUP_GUARD reason=\(failure)\nIN=\(modelInput)\nOUT=\(checked.text)\n".utf8))
                }
                #endif
                return Attempt(text: repairedText, tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                               latencyMs: Self.millis(from: start), prefillMs: result.prefillMs,
                               generationMs: result.generationMs, failure: String(describing: failure))
            }
            if canQuote, config.format.spokenQuotes || modelInput != plan.text, !QuoteGate.preserved(input: modelInput, output: repairedText) {
                return Attempt(text: repairedText, tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                               latencyMs: Self.millis(from: start), prefillMs: result.prefillMs,
                               generationMs: result.generationMs, failure: String(describing: CleanGuard.Failure.quoteChanged))
            }
            let laidOut = ParagraphBoundaries.restore(from: modelInput, in: repairedText)
            return Attempt(text: laidOut, tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                           latencyMs: Self.millis(from: start), prefillMs: result.prefillMs,
                           generationMs: result.generationMs)
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SUPERFLOW_CLEANUP_DEBUG"] == "1" {
                FileHandle.standardError.write(Data("CLEANUP_FALLBACK reason=\(error) input=\(plan.text)\n".utf8))
            }
            #endif
            return Attempt(tokensIn: 0, tokensOut: 0, latencyMs: Self.millis(from: start),
                           failure: String(describing: error))
        }
    }

    /// Cleans a plan. On a guard failure, split the failing plan at sentence
    /// boundaries, retry each leaf one level deeper (up to `config.retryDepth`),
    /// keep the successful leaves and fall back ONLY the leaf that still fails.
    func cleanChunk(_ plan: ChunkPlan, depth: Int = 0, styling: String, structure: String,
                    protected: Protected, context: TextContext) async -> ChunkOutcome {
        let single = await attempt(plan, styling: styling, structure: structure,
                                   protected: protected, context: context)
        if single.failure == nil {
            return ChunkOutcome(index: plan.index, text: single.text, state: .cleaned,
                                tokensIn: single.tokensIn, tokensOut: single.tokensOut,
                                latencyMs: single.latencyMs, attempts: 1,
                                prefillMs: single.prefillMs, generationMs: single.generationMs)
        }
        // Retry on a real split only. `ownedText` excludes the planner's seam
        // overlap, so re-splitting never re-introduces duplicated seam context.
        let source = plan.ownedText.isEmpty ? plan.text : plan.ownedText
        if depth < config.retryDepth, let leaves = Self.sentenceLeaves(source) {
            var combined = ""
            var tokensIn = 0, tokensOut = 0, latency = 0, attempts = 0
            var allCleaned = true
            var firstFailure: String?
            var prefill: Int?, generation: Int?
            for (offset, leaf) in leaves.enumerated() {
                let sub = ChunkPlan(index: offset, text: leaf, tokens: await cleaner.countTokens(leaf))
                let child = await cleanChunk(sub, depth: depth + 1, styling: styling,
                                             structure: structure, protected: protected, context: context)
                if !combined.isEmpty && !child.text.isEmpty { combined += " " }
                combined += child.text
                tokensIn += child.tokensIn
                tokensOut += child.tokensOut
                latency += child.latencyMs
                attempts += child.attempts
                if child.state == .fallback {
                    allCleaned = false
                    if firstFailure == nil { firstFailure = child.reason }
                }
                if prefill == nil { prefill = child.prefillMs }
                if generation == nil { generation = child.generationMs }
            }
            return ChunkOutcome(index: plan.index, text: combined, state: allCleaned ? .cleaned : .fallback,
                                tokensIn: tokensIn, tokensOut: tokensOut, latencyMs: latency,
                                attempts: attempts, reason: firstFailure,
                                prefillMs: prefill, generationMs: generation)
        }
        // Depth exhausted (or unsplittable): the original text is preserved.
        return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback,
                            tokensIn: single.tokensIn, tokensOut: single.tokensOut,
                            latencyMs: single.latencyMs, attempts: 1, reason: single.failure,
                            prefillMs: single.prefillMs, generationMs: single.generationMs)
    }

    private static func sentenceLeaves(_ text: String) -> [String]? {
        let split = SentenceSplitter.split(text)
        var leaves = split.complete.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let tail = split.remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { leaves.append(tail) }
        let useful = leaves.filter { !$0.isEmpty }
        return useful.count >= 2 ? useful : nil
    }

    private static func millis(from start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now)
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
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
