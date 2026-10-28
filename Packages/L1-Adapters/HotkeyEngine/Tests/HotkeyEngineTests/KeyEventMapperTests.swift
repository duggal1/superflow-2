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

    func testLeftCommandIsIgnored() {
        XCTAssertNil(KeyEventMapper.flagsChanged(keyCode: KeyCode.leftCommand, flags: [.maskCommand],
                                                 timestampNs: 1))
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
