import XCTest
@testable import SuperflowKernel

final class VoiceCommandTests: XCTestCase {
    func testOpeningRequiresExactCommand() {
        XCTAssertEqual(VoiceOpeningShortcut.parse("Open WhatsApp."), .whatsapp)
        XCTAssertEqual(VoiceOpeningShortcut.parse("Open Chrome"), .chrome)
        XCTAssertNil(VoiceOpeningShortcut.parse("Please don't open WhatsApp"))
        XCTAssertNil(VoiceOpeningShortcut.parse("Tell me how to open Chrome"))
    }

    func testSendRequiresExplicitTrailingClause() {
        XCTAssertTrue(VoiceSendSuffix.isExplicit("I am on my way. Send it."))
        XCTAssertEqual(VoiceSendSuffix.removing("I am on my way. Send it."), "I am on my way.")
        XCTAssertFalse(VoiceSendSuffix.isExplicit("I will send it."))
        XCTAssertFalse(VoiceSendSuffix.isExplicit("Send it tomorrow."))
        XCTAssertNil(VoiceSendSuffix.removing("Send it."))
    }
}
