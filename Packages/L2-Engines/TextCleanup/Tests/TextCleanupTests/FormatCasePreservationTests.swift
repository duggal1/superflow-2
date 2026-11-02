import XCTest
@testable import SuperflowTextCleanup

final class FormatCasePreservationTests: XCTestCase {
    func testCasingChangesAreRejected() {
        XCTAssertFalse(FormatGuard.preserves("use Swift", "use swift"))
        XCTAssertFalse(FormatGuard.preserves("save the file", "Save the file"))
    }
}
