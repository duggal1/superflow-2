import Foundation
import XCTest
@testable import SuperflowGrammarHarper

final class HarperChunkPlannerTests: XCTestCase {
    func testEmptyTextHasNoChunks() {
        XCTAssertEqual(HarperChunkPlanner.plan(""), [])
    }

    /// Short dictation keeps the single-handle fast path.
    func testShortTextIsOneChunk() {
        let text = "This is a short dictation."
        XCTAssertEqual(HarperChunkPlanner.plan(text),
                       [HarperChunk(utf16Offset: 0, utf16Length: text.utf16.count)])
    }

    func testLongTextSplitsAtSentenceBoundaries() {
        let text = String(repeating: "Alpha beta gamma delta. ", count: 40)
        let chunks = HarperChunkPlanner.plan(text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertLessThanOrEqual(chunks.count, HarperChunkPlanner.maximumChunks)

        var previousEnd = 0
        for chunk in chunks {
            XCTAssertGreaterThan(chunk.utf16Length, 0)
            XCTAssertGreaterThanOrEqual(chunk.utf16Offset, previousEnd)
            previousEnd = chunk.utf16Offset + chunk.utf16Length
            XCTAssertLessThanOrEqual(previousEnd, text.utf16.count)

            let slice = (text as NSString).substring(
                with: NSRange(location: chunk.utf16Offset, length: chunk.utf16Length))
            XCTAssertTrue(slice.hasSuffix(". "), "chunk must end on a sentence edge: \(slice.suffix(8))")
            XCTAssertFalse(slice.hasPrefix(" "), "chunk must start on a sentence edge")
        }
    }

    /// Offsets are UTF-16, so an emoji before the split must not shift the
    /// second chunk's address.
    func testChunkOffsetsAreUTF16AfterEmoji() {
        let text = String(repeating: "😀 This sentence has several words. ", count: 30)
        let chunks = HarperChunkPlanner.plan(text)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            let range = NSRange(location: chunk.utf16Offset, length: chunk.utf16Length)
            let slice = (text as NSString).substring(with: range)
            XCTAssertEqual(slice.utf16.count, chunk.utf16Length)
            XCTAssertFalse(slice.isEmpty)
        }
    }

    /// Without a sentence boundary there is nothing safe to split on, so the
    /// whole string stays on one handle rather than cutting a word.
    func testTextWithoutSentenceBoundaryStaysWhole() {
        let text = String(repeating: "word ", count: 200)
        XCTAssertEqual(HarperChunkPlanner.plan(text),
                       [HarperChunk(utf16Offset: 0, utf16Length: text.utf16.count)])
    }
}

final class HarperLintMergeTests: XCTestCase {
    private func lint(_ start: Int, _ length: Int = 2, kind: String = "Spelling") -> HarperLint {
        HarperLint(utf16Start: start, utf16Length: length, kind: kind, suggestion: nil)
    }

    func testShiftMovesChunkOffsetsBackOntoSource() {
        let shifted = HarperLintMerge.shift([lint(2), lint(8)], by: 100)
        XCTAssertEqual(shifted.map(\.utf16Start), [102, 108])
    }

    func testMergeSortsAndDeduplicates() {
        let merged = HarperLintMerge.merge([lint(5), lint(1), lint(5), lint(5, kind: "Agreement")])
        XCTAssertEqual(merged.map(\.utf16Start), [1, 5, 5])
        XCTAssertEqual(merged.map(\.kind), ["Spelling", "Agreement", "Spelling"])
    }

    func testMergeKeepsDifferentLengthsAtTheSameStart() {
        let merged = HarperLintMerge.merge([lint(3, 2), lint(3, 4)])
        XCTAssertEqual(merged.count, 2)
    }
}
