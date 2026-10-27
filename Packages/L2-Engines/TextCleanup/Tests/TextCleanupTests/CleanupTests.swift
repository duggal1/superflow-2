import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowTextCleanup

final class CleanupTests: XCTestCase {
    private func service(_ cleaner: FakeTextCleaner, config: CleanupConfig = CleanupConfig()) -> CleanupService {
        CleanupService(cleaner: cleaner, config: config)
    }

    func testIdentityIsCleaned() async {
        let cleaner = FakeTextCleaner(.identity)
        let outcome = await service(cleaner).clean("hello world. this is fine.", context: TextContext())
        XCTAssertEqual(outcome.text, "hello world. this is fine.")
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertEqual(outcome.chunks.count, 1)
    }

    func testFailureFallsBackToTier0() async {
        let outcome = await service(FakeTextCleaner(.fail)).clean("keep this text", context: TextContext())
        XCTAssertEqual(outcome.text, "keep this text")
        XCTAssertEqual(outcome.state, .fallback)
    }

    func testTruncationFallsBack() async {
        let input = "one two three four five six seven eight nine ten eleven twelve"
        let outcome = await service(FakeTextCleaner(.truncate)).clean(input, context: TextContext())
        XCTAssertEqual(outcome.text, input)
        XCTAssertEqual(outcome.state, .fallback)
    }

    func testSlowFallsBackAtDeadline() async {
        var config = CleanupConfig()
        config.interactiveDeadlineMs = 40
        let start = Date()
        let outcome = await service(FakeTextCleaner(.slow(ms: 400)), config: config)
            .clean("hello world", context: TextContext())
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(outcome.state, .fallback)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testHallucinationFallsBack() async {
        let outcome = await service(FakeTextCleaner(.echoPrefix("totally invented preamble ")))
            .clean("real words here and more", context: TextContext())
        XCTAssertEqual(outcome.state, .fallback)
    }

    func testDisabledSkips() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let outcome = await service(FakeTextCleaner(.upper))
            .clean("hello", context: TextContext(settings: settings))
        XCTAssertEqual(outcome.text, "hello")
        XCTAssertEqual(outcome.state, .skipped)
    }

    func testPlannerNeverExceedsHardCap() async {
        let planner = ChunkPlanner(config: CleanupConfig(softTokenTarget: 20, hardTokenCap: 30))
        let text = (1...120).map { "word\($0)" }.joined(separator: " ") + "."
        let plans = await planner.plan(text) { input in max(1, wordCount(input)) }
        XCTAssertGreaterThan(plans.count, 1)
        for plan in plans { XCTAssertLessThanOrEqual(plan.tokens, 30, plan.text) }
        XCTAssertEqual(plans.map(\.index), Array(0..<plans.count))
    }

    func testPlannerKeepsOrder() async {
        let planner = ChunkPlanner(config: CleanupConfig(softTokenTarget: 10, hardTokenCap: 20))
        let text = "First sentence here. Second sentence follows. Third sentence ends."
        let plans = await planner.plan(text) { input in max(1, wordCount(input)) }
        XCTAssertEqual(plans.map(\.text).joined(separator: " "), text)
    }

    func testSeamRepair() {
        XCTAssertEqual(SeamRepair.stitch(["Hello world", "world again"]), "Hello world again")
        XCTAssertEqual(SeamRepair.stitch(["Hello", "World"]), "Hello World")
        XCTAssertEqual(SeamRepair.stitch(["Hello.", "World"]), "Hello. World")
    }

    func testStitchRespectsOrder() async {
        let cleaner = FakeTextCleaner(.upper)
        let config = CleanupConfig(softTokenTarget: 8, hardTokenCap: 14)
        let outcome = await service(cleaner, config: config)
            .clean("alpha beta gamma. delta epsilon zeta. eta theta iota.", context: TextContext())
        XCTAssertTrue(outcome.text.hasPrefix("ALPHA"))
        XCTAssertTrue(outcome.text.contains("IOTA"))
    }

    func testEveryChunkResolved() async {
        let config = CleanupConfig(softTokenTarget: 6, hardTokenCap: 12, retryDepth: 1)
        let outcome = await service(FakeTextCleaner(.fail), config: config)
            .clean("one two three. four five six. seven eight nine.", context: TextContext())
        XCTAssertTrue(outcome.chunks.allSatisfy { $0.state == .fallback })
        XCTAssertEqual(wordCount(outcome.text), 9)
    }
}
