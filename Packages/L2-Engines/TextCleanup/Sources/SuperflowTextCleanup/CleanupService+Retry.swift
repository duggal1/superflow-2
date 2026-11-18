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

    /// Per-top-level-chunk retry ledger. Bounds the *total* number of model
    /// requests a chunk may spend across its whole split tree (the old code
    /// only bounded depth, so one bad chunk could fan out to 3^depth calls),
    /// and reuses a successful leaf's result if the same text is seen again.
    actor RetryLedger {
        private let limit: Int
        private var used = 0
        private var results: [String: ChunkOutcome] = [:]

        init(limit: Int) { self.limit = max(1, limit) }

        /// False means the budget is spent; the caller must preserve its raw
        /// text and report a fallback rather than silently skipping the leaf.
        func claim() -> Bool {
            guard used < limit else { return false }
            used += 1
            return true
        }

        func result(for text: String) -> ChunkOutcome? { results[text] }
        func store(_ outcome: ChunkOutcome, for text: String) { results[text] = outcome }
    }

    /// Entry point for one planned chunk: give it its own bounded retry budget.
    func cleanPlan(_ plan: ChunkPlan, styling: String, structure: String,
                   protected: Protected, context: TextContext) async -> ChunkOutcome {
        let ledger = RetryLedger(limit: 1 + max(0, config.retryDepth) * 8)
        return await cleanChunk(plan, depth: 0, styling: styling, structure: structure,
                                protected: protected, context: context, ledger: ledger)
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
            // One protected-literal scan feeds both the quote gate and the
            // guard basis; neither stage re-scans the source.
            let literalRanges = protected.ranges(in: plan.text, detect: false)
            let canQuote = config.format.spokenQuotes && literalRanges.isEmpty
            let modelInput = canQuote
                ? SpokenQuotes.apply(plan.text, style: config.format.quoteStyle)
                : plan.text
            let baseStructure = CleanupStructureDetector.structure(for: plan.text, configured: structure)
            let detectedStructure = structureMapping.structure(
                for: EnumerationDetector.detect(plan.text), base: baseStructure)
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
            let repairedText = RepeatedPathSegment.collapse(result.text)
            let checked = CleanResult(text: repairedText, tokensIn: result.tokensIn,
                                      tokensOut: result.tokensOut, hitTokenCap: result.hitTokenCap,
                                      latencyMs: result.latencyMs, prefillMs: result.prefillMs, generationMs: result.generationMs)
            // Source-side facts (protected spans, list layout, digit/path
            // multisets) are built once here and reused by every ring/fork of
            // this chunk instead of being rebuilt stage by stage.
            let basis = CleanGuard.basis(for: modelInput, protected: protected,
                                         knownLiteralRanges: canQuote ? nil : literalRanges)
            if let failure = CleanGuard.verify(basis: basis, result: checked) {
                return Attempt(text: repairedText, tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                               latencyMs: Self.millis(from: start), prefillMs: result.prefillMs,
                               generationMs: result.generationMs, failure: String(describing: failure))
            }
            if canQuote, !QuoteGate.preserved(input: modelInput, output: repairedText) {
                return Attempt(text: repairedText, tokensIn: result.tokensIn, tokensOut: result.tokensOut,
                               latencyMs: Self.millis(from: start), prefillMs: result.prefillMs,
                               generationMs: result.generationMs, failure: String(describing: CleanGuard.Failure.quoteChanged))
            }
            return Attempt(text: repairedText, tokensIn: result.tokensIn, tokensOut: result.tokensOut,
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

    /// Cleans a plan. On a guard failure, split the failing leaf at sentence
    /// boundaries and retry its children in parallel (bounded by the global
    /// session semaphore), reuse successful sibling results, keep every
    /// successful leaf and fall back ONLY the leaf that still fails.
    func cleanChunk(_ plan: ChunkPlan, depth: Int, styling: String, structure: String,
                    protected: Protected, context: TextContext,
                    ledger: RetryLedger) async -> ChunkOutcome {
        if let reused = await ledger.result(for: plan.text) {
            var copy = reused
            copy.index = plan.index
            return copy
        }
        guard await ledger.claim() else {
            return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback,
                                attempts: 0, reason: "retry budget exhausted")
        }
        let single = await attempt(plan, styling: styling, structure: structure,
                                   protected: protected, context: context)
        if single.failure == nil {
            let outcome = ChunkOutcome(index: plan.index, text: single.text, state: .cleaned,
                                       tokensIn: single.tokensIn, tokensOut: single.tokensOut,
                                       latencyMs: single.latencyMs, attempts: 1,
                                       prefillMs: single.prefillMs, generationMs: single.generationMs)
            await ledger.store(outcome, for: plan.text)
            return outcome
        }
        // `ownedText` excludes the planner's seam overlap, so re-splitting never
        // re-introduces duplicated seam context. A chunk that is itself one
        // complete sentence is a true boundary: never retry it, just fall back.
        let source = plan.ownedText.isEmpty ? plan.text : plan.ownedText
        if depth < config.retryDepth, !Self.isAtomicSentence(source),
           let leaves = Self.sentenceLeaves(source), leaves.count >= 2 {
            let children = await withTaskGroup(of: (Int, ChunkOutcome).self) { group in
                for (offset, leaf) in leaves.enumerated() {
                    group.addTask {
                        let sub = ChunkPlan(index: offset, text: leaf, tokens: await self.cleaner.countTokens(leaf))
                        let child = await self.cleanChunk(sub, depth: depth + 1, styling: styling,
                                                         structure: structure, protected: protected,
                                                         context: context, ledger: ledger)
                        return (offset, child)
                    }
                }
                var ordered = [ChunkOutcome?](repeating: nil, count: leaves.count)
                for await (offset, child) in group { ordered[offset] = child }
                return ordered.compactMap { $0 }
            }
            var combined = ""
            combined.reserveCapacity(source.count)
            var tokensIn = 0, tokensOut = 0, latency = 0, attempts = 1
            var allCleaned = true
            var firstFailure: String?
            var prefill: Int?, generation: Int?
            for child in children {
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
        // Depth exhausted, atomic sentence, or budget spent: the original text
        // is preserved and the failure is reported (never a silent fallback).
        return ChunkOutcome(index: plan.index, text: plan.text, state: .fallback,
                            tokensIn: single.tokensIn, tokensOut: single.tokensOut,
                            latencyMs: single.latencyMs, attempts: 1, reason: single.failure,
                            prefillMs: single.prefillMs, generationMs: single.generationMs)
    }

    /// A single complete sentence carries no safe interior split point.
    private static func isAtomicSentence(_ text: String) -> Bool {
        SentenceSplitter.endsSentence(text) && sentenceLeaves(text) == nil
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
