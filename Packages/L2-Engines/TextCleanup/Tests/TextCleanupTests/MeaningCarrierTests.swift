import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextCleanup

final class MeaningCarrierTests: XCTestCase {
    private func check(_ input: String, _ output: String) -> CleanGuard.Failure? {
        CleanGuard.verify(input: input, protected: Protected(), result: CleanResult(
            text: output, tokensIn: 0, tokensOut: 8, hitTokenCap: false, latencyMs: 0), cap: 100)
    }
    func testPolarityAndQuantifiers() {
        XCTAssertNotNil(check("I did not save the file.", "I did save the file."))
        XCTAssertNotNil(check("we only ship on Thursday.", "We ship on Thursday."))
        XCTAssertNil(check("I didn't save the file.", "I did not save the file."))
    }
    func testNamesAndWordSwaps() {
        XCTAssertNotNil(check("send it to Morgan today.", "Send it to Morris today."))
        XCTAssertNotNil(check("I saved the file properly.", "I saved the file probably."))
        XCTAssertNil(check("yesterday I seen the error in the config.", "Yesterday I saw the error in the config."))
    }
}
