import Foundation
import XCTest

/// Assertion helper that keeps genuine source bugs visible without turning the
/// suite permanently red. A `knownFailure` is documented in the fixture with the
/// offending source location; `strict: false` means an unexpected pass (the bug
/// was fixed) does not fail the run, so the entry can be removed on the next
/// reviewed golden update.
func assertGolden(_ actual: String, _ expected: String, name: String,
                  knownFailure: GoldenCase? = nil,
                  file: StaticString = #filePath, line: UInt = #line) {
    let message = "\(name)\n  expected: \(expected.debugDescription)\n  actual:   \(actual.debugDescription)"
    if let knownFailure {
        let reason = knownFailure.source ?? "see fixture knownFailures"
        XCTExpectFailure("Known source gap for \(name): \(reason)", strict: false) {
            XCTAssertEqual(actual, expected, message, file: file, line: line)
        }
    } else {
        XCTAssertEqual(actual, expected, message, file: file, line: line)
    }
}
