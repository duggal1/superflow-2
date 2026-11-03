import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

final class LongInputBudgetTests: XCTestCase {
    func testHardLimitCannotExceed850Tokens() async {
        var config = CleanupConfig(softTokenTarget: 1000, hardTokenCap: 2000, workers: 4)
        config.hardTokenCap = 2000
        let cleaner = BudgetCleaner()
        let service = CleanupService(cleaner: cleaner, config: config)
        let input = Array(repeating: "word", count: 1700).joined(separator: " ")
        let result = await service.clean(input, context: TextContext(interactive: false))
        let sizes = await cleaner.sizes
        XCTAssertTrue(sizes.allSatisfy { $0 <= 850 }, "\(sizes)")
        XCTAssertEqual(result.text, input)
        XCTAssertEqual(result.state, .cleaned)
    }
    func testMissingLateItemIsRejectedEvenWithoutTokenCap() {
        let source = (1...45).map { "The team reviewed item \($0)." }.joined(separator: " ")
        let incomplete = (1...26).map { "The team reviewed item \($0)." }.joined(separator: " ")
        let result = CleanResult(text: incomplete, tokensIn: 841, tokensOut: 501,
                                 hitTokenCap: false, latencyMs: 0)
        XCTAssertNotNil(CleanGuard.verify(input: source, protected: Protected(), result: result, cap: 1_137))
    }

    func testLongTranscriptsRemainOrderedAndUseParallelWorkers() async {
        for minutes in [10, 30, 60] {
            let cleaner = BudgetCleaner()
            let service = CleanupService(cleaner: cleaner, config: CleanupConfig(workers: 2))
            let input = (0..<(minutes * 150)).map { "word\($0)" }.joined(separator: " ")
            let result = await service.clean(input, context: TextContext(interactive: false))
            let maximum = await cleaner.maximumActive
            let sizes = await cleaner.sizes
            XCTAssertEqual(result.text, input, "\(minutes) minutes")
            XCTAssertEqual(result.state, .cleaned, "\(minutes) minutes")
            XCTAssertTrue(sizes.allSatisfy { $0 <= 850 })
            XCTAssertGreaterThan(sizes.count, 1)
            XCTAssertEqual(maximum, 2)
        }
    }

}

private actor BudgetCleaner: TextCleaner {
    private(set) var sizes: [Int] = []
    private var active = 0
    private(set) var maximumActive = 0
    var isReady: Bool { true }
    func countTokens(_ text: String) async -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
        let size = text.split(whereSeparator: \.isWhitespace).count
        sizes.append(size)
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(2))
        return CleanResult(text: text, tokensIn: size, tokensOut: size, hitTokenCap: false, latencyMs: 1)
    }
}
