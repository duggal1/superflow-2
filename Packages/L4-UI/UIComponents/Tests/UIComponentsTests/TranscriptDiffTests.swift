import SuperflowUIComponents
import XCTest

final class TranscriptDiffTests: XCTestCase {
    func testRemovalAndRewriteProduceHunks() {
        let diff = TranscriptDiff.compute(raw: "um I like cats", cleaned: "I like dogs")
        XCTAssertEqual(diff.hunks.map(\.from), ["um", "cats"])
        XCTAssertEqual(diff.hunks.map(\.to), ["", "dogs"])
        XCTAssertEqual(diff.removed, 2)
        XCTAssertEqual(diff.rewritten, 1)
    }

    func testPunctuationIsPolishedAndWhitespaceIsPreserved() {
        let raw = "  hello\nworld "
        let cleaned = "  Hello,\nworld! "
        let diff = TranscriptDiff.compute(raw: raw, cleaned: cleaned)
        XCTAssertEqual(diff.raw.map { $0.text + $0.gap }.joined(), raw)
        XCTAssertEqual(diff.cleaned.map { $0.text + $0.gap }.joined(), cleaned)
        XCTAssertEqual(diff.polished, 2)
        XCTAssertTrue(diff.hunks.isEmpty)
    }

    func testLargeDiffIsSkipped() {
        let raw = Array(repeating: "raw", count: 2_001).joined(separator: " ")
        let cleaned = Array(repeating: "clean", count: 2_000).joined(separator: " ")
        let diff = TranscriptDiff.compute(raw: raw, cleaned: cleaned)
        XCTAssertTrue(diff.hunks.isEmpty)
        XCTAssertEqual(diff.removed, 0)
        XCTAssertEqual(diff.rewritten, 0)
    }
}
