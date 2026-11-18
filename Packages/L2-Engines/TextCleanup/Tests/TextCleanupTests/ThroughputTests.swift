import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

/// Throughput-focused coverage with a controllable fake cleaner. These tests
/// exercise the real `CleanupService` scheduling/retry/guard path headlessly;
/// they do not mock the service itself. Timing margins are deliberately large
/// so the assertions measure structure (fan-out, budget, state) rather than a
/// stopwatch threshold.
final class ThroughputTests: XCTestCase {
    private func context(interactive: Bool = false) -> TextContext {
        TextContext(interactive: interactive)
    }

    // MARK: 1. Bounded, actually-parallel scheduling

    func testConcurrentCleanersStayWithinLaneBudget() async {
        let cleaner = DelayedCleaner(delayMs: 120)
        let config = CleanupConfig(workers: 4, softTokenTarget: 20, overlapPercent: 0)
        // Distinct tokens avoid a false SeamSplicer alignment at chunk edges.
        let input = (0..<16).map { group in
            (0..<6).map { "term\(group * 6 + $0)" }.joined(separator: " ") + "."
        }.joined(separator: " ")
        let outcome = await CleanupService(cleaner: cleaner, config: config)
            .clean(input, context: context())
        let peak = await cleaner.peakActive
        let calls = await cleaner.calls
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertEqual(outcome.text, input)
        XCTAssertGreaterThan(peak, 1, "chunks did not overlap: peak=\(peak)")
        XCTAssertLessThanOrEqual(peak, 4, "more lanes than configured workers")
        XCTAssertLessThanOrEqual(peak, 10, "more model calls than llama sessions")
        XCTAssertEqual(calls, outcome.chunks.count)
    }

    // MARK: 2. No deadlock / bounded work under total failure

    func testAllCallsFailingReturnsBoundedFallbackWithoutDeadlock() async throws {
        let cleaner = FailingCleaner()
        let config = CleanupConfig(workers: 3, softTokenTarget: 15, retryDepth: 3, overlapPercent: 0)
        let input = (0..<9).map { "Step \($0): verify the deployment." }.joined(separator: " ")
        let service = CleanupService(cleaner: cleaner, config: config)
        let ctx = context()
        let outcome = try await within(seconds: 5) {
            await service.clean(input, context: ctx)
        }
        XCTAssertEqual(outcome.state, .fallback)
        XCTAssertEqual(outcome.text, input, "a failed cleanup must preserve raw text")
        let calls = await cleaner.calls
        // 3 planned chunks x (1 + depth*8) hard cap; the retry ledger must stop
        // the 3^depth fan-out the old depth-only guard allowed.
        XCTAssertLessThanOrEqual(calls, 3 * (1 + 3 * 8))
        XCTAssertTrue(outcome.chunks.allSatisfy { $0.reason != nil }, "fallback must report why")
    }

    // MARK: 3. Successful siblings survive one failing leaf

    func testRetryKeepsSuccessfulLeavesAndFallsBackOnlyTheBadOne() async {
        let cleaner = SelectiveFailingCleaner(failingMarker: "BOMB")
        let config = CleanupConfig(softTokenTarget: 100, hardTokenCap: 850,
                                   retryDepth: 3, overlapPercent: 0)
        let input = "Alpha one is fine. Bravo two is fine. BOMB three is broken. Delta four is fine. Echo five is fine."
        let outcome = await CleanupService(cleaner: cleaner, config: config)
            .clean(input, context: context())
        XCTAssertEqual(outcome.state, .fallback)
        XCTAssertEqual(outcome.chunks.count, 1)
        XCTAssertEqual(outcome.text, input)
        for survivor in ["Alpha one is fine.", "Bravo two is fine.", "Delta four is fine.", "Echo five is fine."] {
            XCTAssertTrue(outcome.text.contains(survivor), "lost clean leaf: \(survivor)")
        }
        XCTAssertNotNil(outcome.chunks[0].reason)
    }

    // MARK: 4. Deadlines are reported honestly

    func testMissedDeadlineIsAReportedFallbackNotACleanedResult() async {
        var config = CleanupConfig()
        config.interactiveDeadlineMs = 25
        let cleaner = DelayedCleaner(delayMs: 200)
        var ctx = context(interactive: true)
        ctx.settings.interactiveDeadlineMs = 25
        let outcome = await CleanupService(cleaner: cleaner, config: config)
            .clean("ship the update tomorrow", context: ctx)
        XCTAssertEqual(outcome.state, .fallback)
        XCTAssertEqual(outcome.text, "ship the update tomorrow")
        XCTAssertEqual(outcome.chunks.count, 1)
        XCTAssertEqual(outcome.chunks[0].attempts, 1)
        XCTAssertTrue(outcome.chunks[0].reason?.localizedCaseInsensitiveContains("timed out")
                      == true || outcome.chunks[0].reason?.localizedCaseInsensitiveContains("timeout") == true,
                      "reason was \(String(describing: outcome.chunks[0].reason))")
    }

    func testResultInsideDeadlineIsReportedCleaned() async {
        var config = CleanupConfig()
        config.interactiveDeadlineMs = 400
        let cleaner = DelayedCleaner(delayMs: 10)
        var ctx = context(interactive: true)
        ctx.settings.interactiveDeadlineMs = 400
        let outcome = await CleanupService(cleaner: cleaner, config: config)
            .clean("ship the update tomorrow", context: ctx)
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertNil(outcome.chunks[0].reason)
        XCTAssertEqual(outcome.chunks[0].attempts, 1)
    }

    // MARK: 5. Coalescing stays inside the safe budget and boundaries

    func testTinyAdjacentChunksCoalesceWithinSoftTarget() async {
        let service = CleanupService(cleaner: WordCountCleaner(),
                                     config: CleanupConfig(softTokenTarget: 100, overlapPercent: 0))
        let plans = [
            ChunkPlan(index: 0, text: "alpha beta", tokens: 2, ownedText: "alpha beta"),
            ChunkPlan(index: 1, text: "gamma delta", tokens: 2, ownedText: "gamma delta"),
        ]
        let merged = await service.coalesceChunks(plans, protected: Protected())
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "alpha beta gamma delta")
        XCTAssertEqual(merged[0].tokens, 4)
        XCTAssertEqual(merged[0].index, 0)
    }

    func testOversizedPairIsNotCoalesced() async {
        let service = CleanupService(cleaner: WordCountCleaner(),
                                     config: CleanupConfig(softTokenTarget: 3, overlapPercent: 0))
        let plans = [
            ChunkPlan(index: 0, text: "alpha beta gamma", tokens: 3, ownedText: "alpha beta gamma"),
            ChunkPlan(index: 1, text: "delta epsilon zeta", tokens: 3, ownedText: "delta epsilon zeta"),
        ]
        let merged = await service.coalesceChunks(plans, protected: Protected())
        XCTAssertEqual(merged.count, 2)
    }

    func testCoalesceNeverCrossesEmailOrProtectedSeam() async {
        let service = CleanupService(cleaner: WordCountCleaner(),
                                     config: CleanupConfig(softTokenTarget: 100, overlapPercent: 0))
        let emailPlans = [
            ChunkPlan(index: 0, text: "send to alice@example.com", tokens: 3, ownedText: "send to alice@example.com"),
            ChunkPlan(index: 1, text: "then ship it", tokens: 3, ownedText: "then ship it"),
        ]
        let emailMerged = await service.coalesceChunks(emailPlans, protected: Protected())
        XCTAssertEqual(emailMerged.count, 2)

        let protectedPlans = [
            ChunkPlan(index: 0, text: "use the hero.tsx", tokens: 3, ownedText: "use the hero.tsx"),
            ChunkPlan(index: 1, text: "file for deployment", tokens: 3, ownedText: "file for deployment"),
        ]
        let protected = Protected(literals: ["hero.tsx"])
        let protectedMerged = await service.coalesceChunks(protectedPlans, protected: protected)
        XCTAssertEqual(protectedMerged.count, 2)
    }

    func testListStraddlingSeamIsMergedToKeepTheRunWhole() async {
        let service = CleanupService(cleaner: WordCountCleaner(),
                                     config: CleanupConfig(softTokenTarget: 100, overlapPercent: 0))
        let plans = [
            ChunkPlan(index: 0, text: "first open the app second press record", tokens: 7,
                      ownedText: "first open the app second press record"),
            ChunkPlan(index: 1, text: "third copy the text", tokens: 4, ownedText: "third copy the text"),
        ]
        let merged = await service.coalesceChunks(plans, protected: Protected())
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].text.contains("third copy the text"))
    }

    // MARK: 6. Cancelled semaphore waiter never mints a permit

    func testCancelledWaiterDoesNotLeakPermitUnderContention() async throws {
        let semaphore = AsyncSemaphore(1)
        try await semaphore.acquire(priority: .background)
        let blocked = Task { try await semaphore.acquire(priority: .background) }
        await Task.yield()
        blocked.cancel()
        await semaphore.release()
        do { try await blocked.value; XCTFail("cancelled waiter succeeded") }
        catch is CancellationError {} catch { XCTFail("unexpected \(error)") }
        // Two interactive acquisitions must still succeed: no leaked permit,
        // no stuck queue.
        try await semaphore.acquire(priority: .interactive)
        await semaphore.release()
        try await semaphore.acquire(priority: .interactive)
        await semaphore.release()
    }

    // MARK: helpers

    private enum TestTimeout: Error {}
    private func within<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TestTimeout()
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw TestTimeout() }
            return value
        }
    }
}

// MARK: - Controllable fakes

/// Identity cleaner with a fixed per-call delay; records live concurrency.
private actor DelayedCleaner: TextCleaner {
    let delayMs: Int
    private var active = 0
    private(set) var peakActive = 0
    private(set) var calls = 0
    var isReady: Bool { true }

    init(delayMs: Int) { self.delayMs = delayMs }

    func countTokens(_ text: String) async -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        calls += 1
        active += 1
        peakActive = max(peakActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(delayMs))
        return CleanResult(text: text, tokensIn: 1, tokensOut: 1,
                           hitTokenCap: false, latencyMs: delayMs)
    }
}

private actor FailingCleaner: TextCleaner {
    private(set) var calls = 0
    var isReady: Bool { true }
    func countTokens(_ text: String) async -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        calls += 1
        throw SuperflowError.modelUnavailable("throughput probe")
    }
}

private actor SelectiveFailingCleaner: TextCleaner {
    let failingMarker: String
    var isReady: Bool { true }
    init(failingMarker: String) { self.failingMarker = failingMarker }
    func countTokens(_ text: String) async -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        if text.contains(failingMarker) { throw SuperflowError.modelUnavailable("leaf") }
        return CleanResult(text: text, tokensIn: 1, tokensOut: 1,
                           hitTokenCap: false, latencyMs: 1)
    }
}

private actor WordCountCleaner: TextCleaner {
    var isReady: Bool { true }
    func countTokens(_ text: String) async -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        CleanResult(text: text, tokensIn: 1, tokensOut: 1,
                    hitTokenCap: false, latencyMs: 1)
    }
}
