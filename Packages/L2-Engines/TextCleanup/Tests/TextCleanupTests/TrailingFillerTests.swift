import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

final class TrailingFillerTests: XCTestCase {
    func testRemovedTrailingFillersAreNotTruncation() {
        for suffix in [" um", " uh um", " hmm."] {
            let result = CleanResult(text: "Please send the report tomorrow.", tokensIn: 0,
                                     tokensOut: 7, hitTokenCap: false, latencyMs: 0)
            XCTAssertNil(CleanGuard.verify(input: "please send the report tomorrow" + suffix,
                                           protected: Protected(), result: result, cap: 100))
        }
    }

    func testMissingContentBeforeFillerStillFails() {
        let result = CleanResult(text: "Please send the report.", tokensIn: 0,
                                 tokensOut: 6, hitTokenCap: false, latencyMs: 0)
        XCTAssertNotNil(CleanGuard.verify(input: "please send the report tomorrow um",
                                          protected: Protected(), result: result, cap: 100))
    }
}
