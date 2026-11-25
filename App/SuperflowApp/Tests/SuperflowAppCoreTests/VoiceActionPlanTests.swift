import XCTest
@testable import SuperflowAppCore

final class VoiceActionPlanTests: XCTestCase {
    func testBrowserSearchPlan() throws {
        let plan = try XCTUnwrap(VoiceActionPlan.parse("Open Safari and find me top 10 shopping malls"))
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertEqual(plan.actions.first, .application("com.apple.Safari"))
        guard let last = plan.actions.last, case .website(let url, let browser) = last else {
            return XCTFail("Expected web search")
        }
        XCTAssertEqual(browser, "com.apple.Safari")
        XCTAssertEqual(url.host, "www.google.com")
    }

    func testUnsupportedCommandsFailClosed() {
        XCTAssertNil(VoiceActionPlan.parse("Delete my files"))
        XCTAssertNil(VoiceActionPlan.parse("Do not open Safari"))
    }
}
