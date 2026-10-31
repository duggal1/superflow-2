import CoreGraphics
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowHotkeyEngine

final class KeyEventMapperTests: XCTestCase {
    func testFnPressAndRelease() {
        let down = KeyEventMapper.flagsChanged(keyCode: KeyCode.fn, flags: [.maskSecondaryFn],
                                               timestampNs: 10)
        XCTAssertEqual(down, KeyEvent(kind: .fnDown, timestampNs: 10))
        let up = KeyEventMapper.flagsChanged(keyCode: KeyCode.fn, flags: [],
                                             timestampNs: 20)
        XCTAssertEqual(up, KeyEvent(kind: .fnUp, timestampNs: 20))
    }

    func testRightCommandPressAndRelease() {
        let down = KeyEventMapper.flagsChanged(keyCode: KeyCode.rightCommand, flags: [.maskCommand],
                                               timestampNs: 30)
        XCTAssertEqual(down, KeyEvent(kind: .rightCmdDown, timestampNs: 30))
        let up = KeyEventMapper.flagsChanged(keyCode: KeyCode.rightCommand, flags: [],
                                             timestampNs: 40)
        XCTAssertEqual(up, KeyEvent(kind: .rightCmdUp, timestampNs: 40))
    }

    /// Releasing right ⌘ while left ⌘ stays held still carries `.maskCommand`.
    /// The keycode tracker is what distinguishes that release from a new press.
    func testRightCommandReleaseWhileLeftCommandHeldIsAnUpEdge() {
        var tracker = ModifierPressTracker()
        XCTAssertTrue(tracker.isDown(keyCode: KeyCode.leftCommand))
        XCTAssertTrue(tracker.isDown(keyCode: KeyCode.rightCommand))
        let release = KeyEventMapper.flagsChanged(
            keyCode: KeyCode.rightCommand, flags: [.maskCommand],
            isDown: tracker.isDown(keyCode: KeyCode.rightCommand), timestampNs: 40)
        XCTAssertEqual(release, KeyEvent(kind: .rightCmdUp, timestampNs: 40))
        // Left ⌘ was never released, so its next edge must be an up edge.
        XCTAssertFalse(tracker.isDown(keyCode: KeyCode.leftCommand))
    }

    func testModifierTrackerTogglesAndResets() {
        var tracker = ModifierPressTracker()
        XCTAssertTrue(tracker.isDown(keyCode: KeyCode.fn))
        XCTAssertFalse(tracker.isDown(keyCode: KeyCode.fn))
        XCTAssertTrue(tracker.isDown(keyCode: KeyCode.fn))
        tracker.reset()
        XCTAssertTrue(tracker.isDown(keyCode: KeyCode.fn))
    }

    func testLeftCommandIsIgnored() {
        XCTAssertNil(KeyEventMapper.flagsChanged(keyCode: KeyCode.leftCommand, flags: [.maskCommand],
                                                 timestampNs: 1))
    }

    /// Every offered key maps onto the same pair the gesture engine already knows,
    /// and Fn falls silent once another key owns dictation.
    func testDictationKeyModifiersMapToDictationEvents() {
        let cases: [(DictationKey, Int64, CGEventFlags)] = [
            (.rightOption, KeyCode.rightOption, .maskAlternate),
            (.rightShift, KeyCode.rightShift, .maskShift),
            (.rightControl, KeyCode.rightControl, .maskControl),
            (.leftOption, KeyCode.leftOption, .maskAlternate),
        ]
        for (key, code, flag) in cases {
            XCTAssertEqual(KeyEventMapper.flagsChanged(keyCode: code, flags: flag,
                                                       timestampNs: 5, dictationKey: key),
                           KeyEvent(kind: .fnDown, timestampNs: 5), "\(key)")
            XCTAssertEqual(KeyEventMapper.flagsChanged(keyCode: code, flags: [],
                                                       timestampNs: 6, dictationKey: key),
                           KeyEvent(kind: .fnUp, timestampNs: 6), "\(key)")
        }

        XCTAssertNil(KeyEventMapper.flagsChanged(keyCode: KeyCode.fn, flags: [.maskSecondaryFn],
                                                 timestampNs: 7, dictationKey: .rightOption))
        XCTAssertNil(KeyEventMapper.flagsChanged(keyCode: KeyCode.rightOption, flags: [.maskAlternate],
                                                 timestampNs: 8, dictationKey: .fn))
        // Right Command stays the meeting key whatever the dictation key is.
        XCTAssertEqual(KeyEventMapper.flagsChanged(keyCode: KeyCode.rightCommand,
                                                   flags: [.maskCommand], timestampNs: 9,
                                                   dictationKey: .rightOption),
                       KeyEvent(kind: .rightCmdDown, timestampNs: 9))
    }

    func testEnterEscapeAndOtherKeys() {
        XCTAssertEqual(KeyEventMapper.keyDown(keyCode: KeyCode.enter, timestampNs: 1),
                       KeyEvent(kind: .enter, timestampNs: 1))
        XCTAssertEqual(KeyEventMapper.keyDown(keyCode: KeyCode.escape, timestampNs: 2),
                       KeyEvent(kind: .escape, timestampNs: 2))
        XCTAssertEqual(KeyEventMapper.keyDown(keyCode: 0x00, timestampNs: 3),
                       KeyEvent(kind: .otherKeyDown(0), timestampNs: 3))
        XCTAssertEqual(KeyEventMapper.keyDown(keyCode: 0x7E, timestampNs: 4),
                       KeyEvent(kind: .otherKeyDown(126), timestampNs: 4))
    }

    func testSyntheticMarkerIsRecognised() throws {
        let source = CGEventSource(stateID: .privateState)
        let marked = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true))
        marked.setIntegerValueField(.eventSourceUserData, value: SyntheticInputMarker.value)
        XCTAssertTrue(KeyEventMapper.isSynthetic(marked))

        let other = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true))
        other.setIntegerValueField(.eventSourceUserData, value: 1234)
        XCTAssertFalse(KeyEventMapper.isSynthetic(other))

        let plain = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true))
        XCTAssertFalse(KeyEventMapper.isSynthetic(plain))
    }
}
