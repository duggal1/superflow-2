import XCTest
@testable import SuperflowTextInsertion

final class AXFocusInspectorTests: XCTestCase {
    func testChromiumFrameworkSignatures() {
        for name in ["Electron Framework", "Google Chrome Framework", "Chromium Embedded Framework.framework",
                     "Microsoft Edge Framework"] {
            XCTAssertTrue(ChromiumDetector.isChromium(frameworkNames: ["Foo.framework", name]), name)
        }
        XCTAssertFalse(ChromiumDetector.isChromium(frameworkNames: ["SwiftUI.framework", "AppKit.framework"]))
    }

    @MainActor
    func testInspectWithInvalidPIDDoesNotCrash() {
        let inspector = AXFocusInspector()
        let result = inspector.inspect(pid: 1)
        switch result.focus {
        case .unknown, .notEditable:
            break
        case .editable, .secure:
            XCTFail("pid 1 should not report an editable field")
        }
    }

    @MainActor
    func testPrepareIsIdempotentPerPID() {
        let inspector = AXFocusInspector()
        inspector.prepare(pid: 1)
        inspector.prepare(pid: 1)
    }
}
