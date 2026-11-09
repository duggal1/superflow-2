import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

final class ChunkConcurrencyTests: XCTestCase {
    func testShortDictationUsesOneChunkAndLongTranscriptFansOut() async {
        let cleaner = CountingChunkCleaner()
        let service = CleanupService(cleaner: cleaner)
        let short = Array(repeating: "word", count: 200).joined(separator: " ")
        let longer = Array(repeating: "word", count: 1_700).joined(separator: " ")
        let shortResult = await service.clean(short, context: TextContext(interactive: false))
        let longResult = await service.clean(longer, context: TextContext(interactive: false))
        XCTAssertEqual(shortResult.chunks.count, 1)
        // The 800-token dynamic target packs a 1,700-word transcript into 3
        // parallel chunks instead of ~7 small ones.
        XCTAssertEqual(longResult.chunks.count, 3)
        XCTAssertEqual(longResult.text, longer)
        XCTAssertTrue(longResult.chunks.allSatisfy { $0.tokensIn <= 850 })
        let active = await cleaner.maxActive
        XCTAssertEqual(active, 3)
    }

    func testWorkerCountClampsToSixAvailableRuntimeContexts() async {
        let cleaner = CountingChunkCleaner()
        let input = Array(repeating: "word", count: 5_600).joined(separator: " ")
        let outcome = await CleanupService(cleaner: cleaner,
                                           config: CleanupConfig(workers: 8))
            .clean(input, context: TextContext(interactive: false))
        XCTAssertEqual(outcome.text, input)
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertEqual(outcome.chunks.count, 7)
        let maxActive = await cleaner.maxActive
        XCTAssertEqual(maxActive, 6)
        XCTAssertTrue(outcome.chunks.allSatisfy { $0.attempts == 1 })
    }

    func testTwoHundredFiftyTokensUseOneChunkAndFiveHundredUseTwoWorkers() async {
        let cleaner = CountingChunkCleaner()
        let service = CleanupService(cleaner: cleaner, config: CleanupConfig(softTokenTarget: 250))
        let short = Array(repeating: "word", count: 250).joined(separator: " ")
        let long = Array(repeating: "word", count: 500).joined(separator: " ")
        let shortResult = await service.clean(short, context: TextContext(interactive: false))
        XCTAssertEqual(shortResult.chunks.count, 1)
        XCTAssertEqual(shortResult.text, short)
        let longResult = await service.clean(long, context: TextContext(interactive: false))
        XCTAssertEqual(longResult.chunks.count, 2)
        XCTAssertEqual(longResult.text, long)
        XCTAssertTrue(longResult.chunks.allSatisfy { $0.state == .cleaned && $0.tokensIn <= 250 })
        let maxActive = await cleaner.maxActive
        XCTAssertEqual(maxActive, 2)
    }
    func testTokenHeavyWordsDoNotTriggerLinearTokenizerCalls() async {
        let counter = TokenHeavyCounter()
        var config = CleanupConfig(softTokenTarget: 250)
        config.overlapPercent = 0
        let input = Array(repeating: "word", count: 250).joined(separator: " ")
        let plans = await ChunkPlanner(config: config).plan(input) { await counter.count($0) }
        let calls = await counter.calls
        XCTAssertEqual(plans.map(\.text).joined(separator: " "), input)
        XCTAssertTrue(plans.allSatisfy { $0.tokens <= 250 })
        XCTAssertLessThanOrEqual(calls, 50)
    }

    func testProtectedSpanMayExceedTargetWithoutBeingSplit() async {
        let cleaner = CountingChunkCleaner()
        let service = CleanupService(cleaner: cleaner)
        let phrase = Array(repeating: "word", count: 300).joined(separator: " ")
        let result = await service.clean(phrase, protected: Protected(literals: [phrase]),
                                         context: TextContext(interactive: false))
        XCTAssertEqual(result.chunks.count, 1)
        XCTAssertEqual(result.text, phrase)
        XCTAssertEqual(result.state, .cleaned)
    }
}

private actor CountingChunkCleaner: TextCleaner {
    private var active = 0
    private(set) var maxActive = 0
    var isReady: Bool { true }
    func countTokens(_ text: String) async -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        active += 1
        maxActive = max(maxActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(30))
        return CleanResult(text: text, tokensIn: text.split(whereSeparator: \.isWhitespace).count,
                           tokensOut: 1, hitTokenCap: false, latencyMs: 30)
    }
}

private actor TokenHeavyCounter {
    private(set) var calls = 0
    func count(_ text: String) -> Int {
        calls += 1
        return text.split(whereSeparator: \.isWhitespace).count * 4
    }
}
