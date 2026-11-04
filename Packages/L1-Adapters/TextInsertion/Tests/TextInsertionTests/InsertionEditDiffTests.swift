import XCTest
@testable import SuperflowTextInsertion

final class InsertionEditDiffTests: XCTestCase {
    func testOnlyChangesInsideKnownInsertedSpanBecomeCorrections() throws {
        let inserted = "please use next year today."
        let before = "Existing note. " + inserted + " Thank you."
        let after = "Existing note. please use Next.js today. Thank you."
        let observed = try XCTUnwrap(InsertionEditDiff.correction(
            before: before, after: after, inserted: inserted,
            bundleID: "com.apple.TextEdit", anchorID: "session-one"))
        XCTAssertEqual(observed.heard, "next year")
        XCTAssertEqual(observed.corrected, "Next.js")
        XCTAssertEqual(observed.appBundleID, "com.apple.TextEdit")
        XCTAssertEqual(observed.anchorID, "session-one")
    }

    func testEditsOutsideInsertionNeverTeachDictionary() {
        let inserted = "inserted phrase"
        let before = "Old notes. inserted phrase. More notes."
        let after = "New notes. inserted phrase. More notes."
        XCTAssertNil(InsertionEditDiff.correction(before: before, after: after, inserted: inserted,
                                                 bundleID: nil, anchorID: "a"))
    }

    func testDuplicateAnchorAndLargeDocumentAreIgnored() {
        let before = "one one"
        let after = "one two"
        XCTAssertNil(InsertionEditDiff.correction(before: before, after: after,
                                                 inserted: "one", bundleID: nil, anchorID: "a"))
        let large = String(repeating: "x", count: 513) + " phrase"
        XCTAssertNil(InsertionEditDiff.correction(
            before: large, after: large.replacingOccurrences(of: "phrase", with: "term"),
            inserted: "phrase", bundleID: nil, anchorID: "b"))
    }

    func testNoCorrectionWithoutActualEditOrRecognizedInsertion() {
        XCTAssertNil(InsertionEditDiff.correction(
            before: "hello", after: "hello", inserted: "hello",
            bundleID: nil, anchorID: "a"))
        XCTAssertNil(InsertionEditDiff.correction(
            before: "hello", after: "HELLO", inserted: "other",
            bundleID: nil, anchorID: "a"))
    }
}
