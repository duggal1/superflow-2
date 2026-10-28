import Foundation
import SuperflowKernel
import SuperflowTestKit
import SuperflowTextCleanup
import XCTest

final class CleanupGoldenTests: XCTestCase {
    private func fixture() throws -> CleanupFixture {
        try Golden.load("cleanup/cases.json")
    }

    private func settings() -> AppSettings {
        var settings = Golden.stageSettings()
        settings.cleanupEnabled = true
        return settings
    }

    func testCleanupCorpus() async throws {
        let fixture = try fixture()
        let config = fixture.config?.config() ?? CleanupConfig()
        for c in fixture.cases {
            let service = CleanupService(cleaner: c.behavior.cleaner(), config: config)
            let outcome = await service.clean(c.input, context: TextContext(settings: settings()))
            if let minimum = c.minimumChunks {
                XCTAssertGreaterThanOrEqual(outcome.chunks.count, minimum,
                                            "expected at least \(minimum) chunk(s) for \(c.name)")
            }
            XCTAssertEqual(outcome.state, c.expectedState, "state differs for \(c.name)")
            XCTAssertEqual(outcome.text, c.expected, "text differs for \(c.name)")
        }
    }

    func testDeadlineBoundsInteractiveLatency() async throws {
        let fixture = try fixture()
        let config = fixture.config?.config() ?? CleanupConfig()
        let service = CleanupService(cleaner: FakeTextCleaner(.slow(ms: 2_000)), config: config)
        let started = DispatchTime.now().uptimeNanoseconds
        let outcome = await service.clean("the quick brown fox jumps over the lazy dog",
                                          context: TextContext(settings: settings()))
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        XCTAssertEqual(outcome.state, .fallback)
        XCTAssertLessThan(elapsedMs, 1_500, "interactive cleanup exceeded its deadline budget")
    }

    func testDisabledCleanupSkipsTheModel() async {
        var disabled = settings()
        disabled.cleanupEnabled = false
        let service = CleanupService(cleaner: FakeTextCleaner(.upper))
        let outcome = await service.clean("hello world", context: TextContext(settings: disabled))
        XCTAssertEqual(outcome.state, .skipped)
        XCTAssertEqual(outcome.text, "hello world")
    }

    func testEmptyInputSkipsTheModel() async {
        let service = CleanupService(cleaner: FakeTextCleaner(.upper))
        for input in ["", "   ", "\n"] {
            let outcome = await service.clean(input, context: TextContext(settings: settings()))
            XCTAssertEqual(outcome.state, .skipped)
            XCTAssertEqual(outcome.text, "")
            XCTAssertTrue(outcome.chunks.isEmpty)
        }
    }

    func testChunkPlannerNeverSplitsProtectedSpans() async {
        let config = CleanupConfig(softTokenTarget: 10, hardTokenCap: 20)
        let planner = ChunkPlanner(config: config, protected: Protected(literals: ["Superflow"]))
        let prefix = (1...30).map { "word\($0)" }.joined(separator: " ")
        let suffix = (1...30).map { "tail\($0)" }.joined(separator: " ")
        let text = "\(prefix) Superflow \(suffix)"
        let plans = await planner.plan(text) { text in max(1, Tokenizer.words(in: text).count) }
        XCTAssertGreaterThan(plans.count, 1)
        for plan in plans {
            let hasPartial = plan.text.contains("Super") && !plan.text.contains("Superflow")
            XCTAssertFalse(hasPartial, "chunk split inside the protected span: \(plan.text)")
            XCTAssertLessThanOrEqual(plan.tokens, 20, "chunk exceeds the hard token cap: \(plan.text)")
        }
        XCTAssertEqual(plans.map(\.index), Array(0..<plans.count), "chunk indices are not contiguous")
        // Chunks after the first repeat their seam overlap, so the joined
        // bodies contain those words again once. Subtracting them must return
        // exactly the input: nothing lost, nothing invented.
        let overlapWords = plans.dropFirst().reduce(0) { $0 + $1.overlap.split(separator: " ").count }
        XCTAssertEqual(plans.map(\.text).joined(separator: " ").split(separator: " ").count - overlapWords,
                       text.split(separator: " ").count, "chunk planner lost words")
    }

    func testEveryChunkResolvesInOrder() async throws {
        let words = (1...300).map { "word\($0)" }
        let input = words.joined(separator: " ")
        let config = CleanupConfig(softTokenTarget: 20, hardTokenCap: 40, workers: 4)
        let service = CleanupService(cleaner: FakeTextCleaner(.upper), config: config)
        let outcome = await service.clean(input, context: TextContext(settings: settings()))
        XCTAssertGreaterThan(outcome.chunks.count, 1)
        XCTAssertTrue(outcome.chunks.allSatisfy { $0.state == .cleaned })
        XCTAssertEqual(outcome.chunks.map(\.index), Array(0..<outcome.chunks.count))
        XCTAssertEqual(outcome.text, input.uppercased())
    }

    func testOutputIsBoundedRelativeToInput() async throws {
        let fixture = try fixture()
        let config = fixture.config?.config() ?? CleanupConfig()
        for c in fixture.cases where c.expectedState != .cleaned {
            let service = CleanupService(cleaner: c.behavior.cleaner(), config: config)
            let outcome = await service.clean(c.input, context: TextContext(settings: settings()))
            XCTAssertLessThanOrEqual(outcome.text.count, c.input.count + 8,
                                     "fallback text grew for \(c.name)")
        }
    }
}
