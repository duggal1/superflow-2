import XCTest
@testable import SuperflowTextInsertion

final class AXValueReplacementTests: XCTestCase {
    func testReplacesSelectedRange() {
        XCTAssertEqual(AXValueReplacement.replacing(value: "hello world", range: (6, 5), with: "there"),
                       "hello there")
    }

    func testClampsOutOfBoundsRange() {
        XCTAssertEqual(AXValueReplacement.replacing(value: "hello", range: (3, 99), with: "p"),
                       "help")
        XCTAssertEqual(AXValueReplacement.replacing(value: "hello", range: (99, 4), with: "!"),
                       "hello!")
    }

    func testAppendsWhenNoRange() {
        XCTAssertEqual(AXValueReplacement.replacing(value: "hello", range: nil, with: " world"),
                       "hello world")
    }
}
