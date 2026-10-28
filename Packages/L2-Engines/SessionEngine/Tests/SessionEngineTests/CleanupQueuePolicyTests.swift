import XCTest
@testable import SuperflowSessionEngine

final class CleanupQueuePolicyTests: XCTestCase {
    func testInteractiveJumpsAheadOfBackground() {
        XCTAssertEqual(
            CleanupQueuePolicy.insertionIndex(isInteractive: true,
                                              queued: [false, false, false]), 0)
    }

    func testInteractiveDoesNotJumpAheadOfEarlierInteractiveWork() {
        XCTAssertEqual(
            CleanupQueuePolicy.insertionIndex(isInteractive: true,
                                              queued: [true, true, false, false]), 2)
    }

    func testInteractiveWithNoBackgroundQueuedGoesToTheBack() {
        XCTAssertEqual(
            CleanupQueuePolicy.insertionIndex(isInteractive: true, queued: [true, true]), 2)
    }

    func testBackgroundAlwaysGoesToTheBack() {
        XCTAssertEqual(
            CleanupQueuePolicy.insertionIndex(isInteractive: false,
                                              queued: [true, false, true]), 3)
    }

    func testEmptyQueueUsesTheFront() {
        XCTAssertEqual(
            CleanupQueuePolicy.insertionIndex(isInteractive: true, queued: []), 0)
    }
}
