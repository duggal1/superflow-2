import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

final class ChunkConcurrencyTests: XCTestCase {
    func testTwoHundredFiftyTokensUseOneChunkAndFiveHundredUseTwoWorkers() async {
        let cleaner = CountingChunkCleaner()
        let service = CleanupService(cleaner: cleaner)
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
        var config = CleanupConfig()
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
