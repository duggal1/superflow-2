import XCTest
import SuperflowClearlyInput

/// Pure mapping tests: no CGEventTap, no permissions, no GUI.
final class ClearlyInputMappingTests: XCTestCase {
    private func map(_ code: Int64, _ flags: UInt64,
                     _ kind: RawKeyEventMapper.EventKind, _ t: Double = 1) -> Clearly.RawEvent {
        RawKeyEventMapper.map(keyCode: code, flags: flags, kind: kind, timestamp: t)
    }

    func testRightOptionUsesDeviceBit() {
        XCTAssertEqual(map(61, RawKeyEventMapper.rightOptionDeviceBit, .flagsChanged),
                       Clearly.RawEvent(.rightOptionDown, at: 1))
        XCTAssertEqual(map(61, 0, .flagsChanged),
                       Clearly.RawEvent(.rightOptionUp, at: 1))
        // Left Option's bit (0x20) alone must never look like Right Option.
        XCTAssertEqual(map(61, 0x20, .flagsChanged),
                       Clearly.RawEvent(.rightOptionUp, at: 1))
    }

    func testLeftControlUsesDeviceBit() {
        XCTAssertEqual(map(59, RawKeyEventMapper.leftControlDeviceBit, .flagsChanged),
                       Clearly.RawEvent(.leftControlDown, at: 1))
        XCTAssertEqual(map(59, 0, .flagsChanged),
                       Clearly.RawEvent(.leftControlUp, at: 1))
        // Right Control's bit (0x2000) alone must never look like Left Control.
        XCTAssertEqual(map(59, 0x2000, .flagsChanged),
                       Clearly.RawEvent(.leftControlUp, at: 1))
    }

    func testLeftOptionAndRightControlDoNothing() {
        // As flag changes they are interference; in `idle` the recognizer emits
        // nothing, which is what "do nothing" means to the user.
        XCTAssertEqual(map(58, 0x20, .flagsChanged),
                       Clearly.RawEvent(.interference, at: 1))
        XCTAssertEqual(map(62, 0x2000, .flagsChanged),
                       Clearly.RawEvent(.interference, at: 1))
    }

    func testAnyKeyDown_isInterference() {
        // Option+E: E is a keyDown, reported as interference so a held PTT cancels.
        XCTAssertEqual(map(0x0E, 0, .keyDown), Clearly.RawEvent(.interference, at: 1))
        XCTAssertEqual(map(0x24, 0, .keyDown), Clearly.RawEvent(.interference, at: 1))
    }

    func testMouseDown_isInterference() {
        // Ctrl+click: the click is a mouseDown, disarming a pending Left Control.
        XCTAssertEqual(map(0, 0, .mouseDown), Clearly.RawEvent(.interference, at: 1))
    }

    func testConstantsMatchTheLockedBindings() {
        XCTAssertEqual(RawKeyEventMapper.rightOptionKeyCode, 61)
        XCTAssertEqual(RawKeyEventMapper.leftControlKeyCode, 59)
        XCTAssertEqual(RawKeyEventMapper.leftOptionKeyCode, 58)
        XCTAssertEqual(RawKeyEventMapper.rightControlKeyCode, 62)
        XCTAssertEqual(RawKeyEventMapper.rightOptionDeviceBit, 0x40)
        XCTAssertEqual(RawKeyEventMapper.leftControlDeviceBit, 0x01)
    }
}
