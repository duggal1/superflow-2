import XCTest
import SuperflowClearlyInput

/// Exhaustive coverage of every row in the ClearlyInput gesture table.
/// Pure and headless: no event tap, no app launch, no keystrokes.
final class ClearlyInputGestureTests: XCTestCase {
    private let config = Clearly.Config(
        holdThreshold: 0.25, ctrlTapMax: 0.5, ctrlDebounce: 0.4, maxListen: 120
    )

    private func recognizer() -> Clearly.Recognizer { Clearly.Recognizer(config: config) }
    private func ev(_ key: Clearly.RawKey, _ t: Double) -> Clearly.RawEvent {
        Clearly.RawEvent(key, at: t)
    }

    // MARK: - Push-to-talk

    func testIdleRightOptionDown_becomesPressed_andEmitsBegan() {
        var g = recognizer()
        XCTAssertEqual(g.ptt, .idle)
        XCTAssertEqual(g.handle(ev(.rightOptionDown, 10)), [.pttBegan])
        XCTAssertEqual(g.ptt, .pressed)
    }

    func testPressedInterference_cancels() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        // Option+E: the E keyDown is reported as interference.
        XCTAssertEqual(g.handle(ev(.interference, 0.08)), [.pttCancelled])
        XCTAssertEqual(g.ptt, .idle)
        XCTAssertEqual(g.handle(ev(.interference, 0.09)), [])
    }

    func testPressedReleaseAfterHold_sends() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        XCTAssertEqual(g.handle(ev(.rightOptionUp, 0.25)), [.pttSend])
        XCTAssertEqual(g.ptt, .idle)
    }

    func testPressedReleaseBeforeHold_latches() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        XCTAssertEqual(g.handle(ev(.rightOptionUp, 0.2499)), [.pttLatched])
        XCTAssertEqual(g.ptt, .latched)
    }

    func testLatchedPress_doesNothing_andArmsSend() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        _ = g.handle(ev(.rightOptionUp, 0.05))       // latched
        XCTAssertEqual(g.handle(ev(.rightOptionDown, 1.0)), [])
        XCTAssertEqual(g.ptt, .latchedDown)
        XCTAssertEqual(g.handle(ev(.rightOptionUp, 1.1)), [.pttSend])
        XCTAssertEqual(g.ptt, .idle)
    }

    func testLatchedInterference_doesNothing() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        _ = g.handle(ev(.rightOptionUp, 0.05))
        XCTAssertEqual(g.handle(ev(.interference, 0.2)), [])
        XCTAssertEqual(g.ptt, .latched)
    }

    func testLatchedDownInterference_doesNothing() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        _ = g.handle(ev(.rightOptionUp, 0.05))
        _ = g.handle(ev(.rightOptionDown, 0.2))
        XCTAssertEqual(g.handle(ev(.interference, 0.25)), [])
        XCTAssertEqual(g.ptt, .latchedDown)
        // And it still sends on release.
        XCTAssertEqual(g.handle(ev(.rightOptionUp, 0.3)), [.pttSend])
    }

    func testLatchedTimeout_sends() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        _ = g.handle(ev(.rightOptionUp, 0.05))
        XCTAssertEqual(g.tick(at: 119.99), [])
        XCTAssertEqual(g.ptt, .latched)
        XCTAssertEqual(g.tick(at: 120.05), [.pttSend])
        XCTAssertEqual(g.ptt, .idle)
        XCTAssertEqual(g.tick(at: 121), [])
    }

    func testOptionPlusKey_thenFreshPress_stillWorks() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        XCTAssertEqual(g.handle(ev(.interference, 0.01)), [.pttCancelled])
        XCTAssertEqual(g.handle(ev(.rightOptionDown, 0.5)), [.pttBegan])
        XCTAssertEqual(g.handle(ev(.rightOptionUp, 1.0)), [.pttSend])
    }

    func testLeftOptionAndRightControl_areInterference_noGesturesInIdle() {
        var g = recognizer()
        XCTAssertEqual(g.handle(ev(.interference, 0)), [])
        XCTAssertEqual(g.handle(ev(.interference, 0.1)), [])
        XCTAssertEqual(g.ptt, .idle)
        XCTAssertEqual(g.ctrl, .idle)
    }

    func testRepeatedPTTCycles_doNotLeakState() {
        var g = recognizer()
        for i in 0..<5 {
            let base = Double(i) * 10
            XCTAssertEqual(g.handle(ev(.rightOptionDown, base)), [.pttBegan])
            XCTAssertEqual(g.handle(ev(.rightOptionUp, base + 0.4)), [.pttSend])
            XCTAssertEqual(g.ptt, .idle)
        }
    }

    // MARK: - Meeting toggle

    func testIdleLeftControlDown_armsWithoutGesture() {
        var g = recognizer()
        XCTAssertEqual(g.handle(ev(.leftControlDown, 0)), [])
        XCTAssertEqual(g.ctrl, .pressed)
    }

    func testCtrlPressedInterference_ignored() {
        var g = recognizer()
        _ = g.handle(ev(.leftControlDown, 0))
        // Ctrl+click is a right-click; it must not toggle a meeting.
        XCTAssertEqual(g.handle(ev(.interference, 0.02)), [])
        XCTAssertEqual(g.ctrl, .idle)
    }

    func testCtrlTap_toggles() {
        var g = recognizer()
        _ = g.handle(ev(.leftControlDown, 0))
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0.2)), [.meetingToggle])
        XCTAssertEqual(g.ctrl, .idle)
    }

    func testCtrlLongHold_doesNotToggle() {
        var g = recognizer()
        _ = g.handle(ev(.leftControlDown, 0))
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0.5)), [])
        XCTAssertEqual(g.ctrl, .idle)
    }

    func testCtrlToggleDebounce_suppressesRapidRepeat() {
        var g = recognizer()
        _ = g.handle(ev(.leftControlDown, 0))
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0.1)), [.meetingToggle])
        // A new tap only 0.2 s after the last toggle is inside the debounce.
        _ = g.handle(ev(.leftControlDown, 0.25))
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0.35)), [])
        // After 0.4 s the toggle works again.
        _ = g.handle(ev(.leftControlDown, 0.60))
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0.70)), [.meetingToggle])
    }

    func testCtrlStrayUp_doesNothing() {
        var g = recognizer()
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0)), [])
        XCTAssertEqual(g.ctrl, .idle)
    }

    // MARK: - Independence

    func testPTTduringMeeting_isIndependent() {
        var g = recognizer()
        _ = g.handle(ev(.leftControlDown, 0))
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0.1)), [.meetingToggle])
        XCTAssertEqual(g.handle(ev(.rightOptionDown, 1)), [.pttBegan])
        XCTAssertEqual(g.handle(ev(.rightOptionUp, 1.3)), [.pttSend])
        XCTAssertEqual(g.ctrl, .idle)
        XCTAssertEqual(g.ptt, .idle)
    }

    func testInterferenceCancelsPTT_andDisarmsCtrlTogether() {
        var g = recognizer()
        _ = g.handle(ev(.rightOptionDown, 0))
        _ = g.handle(ev(.leftControlDown, 0))
        XCTAssertEqual(g.handle(ev(.interference, 0.01)), [.pttCancelled])
        XCTAssertEqual(g.ptt, .idle)
        XCTAssertEqual(g.ctrl, .idle)
        XCTAssertEqual(g.handle(ev(.leftControlUp, 0.05)), [])
    }
}
