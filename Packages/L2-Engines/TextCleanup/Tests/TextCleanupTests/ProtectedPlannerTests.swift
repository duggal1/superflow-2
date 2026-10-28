import XCTest
import SuperflowKernel
@testable import SuperflowTextCleanup

final class ProtectedPlannerTests: XCTestCase {
    func testWordPunctuationRoundTrip() {
        let text = "(hero.tsx), '$23,450' C++ …"
        XCTAssertEqual(Tokenizer.join(Tokenizer.words(text)), text)
    }

    func testCodeAndNumbersAreProtectedWithoutExplicitLiterals() {
        let words = Tokenizer.words("open hero.tsx for $23,450 and 500")
        XCTAssertEqual(words.map(\.protected), [false, true, false, true, false, true])
    }

    func testLiteralMarksEveryWordAndGluesItsInterior() {
        let words = Tokenizer.words("use TanStack Query now", protected: Protected(literals: ["TanStack Query"]))
        XCTAssertEqual(words.map(\.protected), [false, true, true, false])
        XCTAssertEqual(words.map(\.glue), [false, true, false, false])
    }

    func testOwnedBodiesPreserveEveryWordExactlyOnce() async {
        let original = (0..<6_000).map { "word\($0)" }.joined(separator: " ")
        let plans = await ChunkPlanner(config: CleanupConfig(softTokenTarget: 50, hardTokenCap: 80))
            .plan(original) { $0.split(whereSeparator: \.isWhitespace).count }
        XCTAssertEqual(plans.map(\.ownedText).joined(separator: " "), original)
        XCTAssertTrue(plans.allSatisfy { $0.tokens <= 80 })
        XCTAssertGreaterThan(plans.count, 1)
    }

    func testHugeProtectedSpanNeverSplits() async {
        let literal = (0..<100).map { "term\($0)" }.joined(separator: " ")
        let input = "before " + literal + " after"
        let plans = await ChunkPlanner(config: CleanupConfig(softTokenTarget: 10, hardTokenCap: 20),
                                       protected: Protected(literals: [literal]))
            .plan(input) { $0.split(whereSeparator: \.isWhitespace).count }
        XCTAssertEqual(plans.map(\.ownedText).joined(separator: " "), input)
        XCTAssertTrue(plans.contains { $0.ownedText.contains(literal) })
    }

    func testGlueIsNeverCutEvenWhenEveryCandidateIsGlued() async {
        var words = Tokenizer.words("alpha beta gamma delta epsilon zeta eta theta iota kappa")
        for index in 0..<8 { words[index].glue = true }
        let plans = await ChunkPlanner(config: CleanupConfig(softTokenTarget: 3, hardTokenCap: 5))
            .plan(words) { $0.split(whereSeparator: \.isWhitespace).count }
        XCTAssertEqual(plans.first?.ownedText, "alpha beta gamma delta epsilon zeta eta theta iota")
        XCTAssertEqual(plans.map(\.ownedText).joined(separator: " "), Tokenizer.join(words))
    }
}
