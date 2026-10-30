import CoreGraphics
import XCTest
@testable import SuperflowTextInsertion

@MainActor
final class InsertionTypesTests: XCTestCase {
    func testOptionsDefaults() {
        let options = TextInsertionOptions()
        XCTAssertNil(options.targetPID)
        XCTAssertTrue(options.restoreClipboard)
        XCTAssertEqual(options.clipboardRestoreDelay, .milliseconds(500))
        XCTAssertEqual(options.verifiedRestoreDelay, .milliseconds(50))
        XCTAssertEqual(options.verifyTimeout, .milliseconds(400))
        XCTAssertEqual(options.modifierReleaseTimeout, .milliseconds(300))
        XCTAssertTrue(options.allowPaste)
        XCTAssertFalse(options.preferAccessibility)
        XCTAssertTrue(options.preferAccessibilityForEditable)
        XCTAssertTrue(options.allowAccessibilityFallback)
        XCTAssertTrue(options.writeClipboardOnFailure)
        XCTAssertEqual(options.postTap, .cgSessionEventTap)
    }

    func testOnlyEditableFocusIsConfident() {
        XCTAssertTrue(InsertionFocus.editable(role: "AXTextArea").isConfidentEditable)
        XCTAssertFalse(InsertionFocus.unknown(reason: "role-AXGroup").isConfidentEditable)
        XCTAssertFalse(InsertionFocus.notEditable(reason: "role-AXButton").isConfidentEditable)
        XCTAssertFalse(InsertionFocus.secure.isConfidentEditable)
    }

    func testFocusDistinguishesSecureFromEditable() {
        XCTAssertNotEqual(InsertionFocus.secure, .editable(role: "AXTextArea"))
        XCTAssertEqual(InsertionFocus.editable(role: "AXTextArea"), .editable(role: "AXTextArea"))
        XCTAssertEqual(InsertionFocus.unknown(reason: "x"), .unknown(reason: "x"))
    }

    func testLayoutResolverReturnsARealKeyCode() {
        let resolver = LayoutPasteKeyResolver()
        let code = resolver.pasteKeyCode()
        XCTAssertTrue((0..<128).contains(Int(code)))
        XCTAssertEqual(LayoutPasteKeyResolver.fallbackKeyCode, 9)
    }
}
