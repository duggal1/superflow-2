import XCTest
@testable import SuperflowClearlyInput

/// The same exhaustive table used by the app-level ClearlyInput tests, kept
/// here so the L0-only package can be verified on its own.
final class GestureTableTests: XCTestCase {
    private func r(_ key: Clearly.RawKey, _ t: Double) -> Clearly.RawEvent {
        Clearly.RawEvent(key, at: t)
    }

    func testPushToTalkTable() {
        var g = Clearly.Recognizer()

        XCTAssertEqual(g.handle(r(.rightOptionDown, 0)), [.pttBegan])
        XCTAssertEqual(g.ptt, .pressed)
        XCTAssertEqual(g.handle(r(.rightOptionUp, 0.30)), [.pttSend])
        XCTAssertEqual(g.ptt, .idle)

        XCTAssertEqual(g.handle(r(.rightOptionDown, 1)), [.pttBegan])
        XCTAssertEqual(g.handle(r(.rightOptionUp, 1.10)), [.pttLatched])
        XCTAssertEqual(g.ptt, .latched)
        XCTAssertEqual(g.handle(r(.rightOptionDown, 1.20)), [])
        XCTAssertEqual(g.ptt, .latchedDown)
        XCTAssertEqual(g.handle(r(.rightOptionUp, 1.30)), [.pttSend])
        XCTAssertEqual(g.ptt, .idle)
    }

    func testInterferenceCancelsPressedOnly() {
        var g = Clearly.Recognizer()
        _ = g.handle(r(.rightOptionDown, 0))
        XCTAssertEqual(g.handle(r(.interference, 0.02)), [.pttCancelled])
        XCTAssertEqual(g.ptt, .idle)
        XCTAssertEqual(g.handle(r(.interference, 0.03)), [])

        _ = g.handle(r(.rightOptionDown, 1))
        _ = g.handle(r(.rightOptionUp, 1.05))   // latched
        XCTAssertEqual(g.handle(r(.interference, 1.1)), [])
        XCTAssertEqual(g.ptt, .latched)
    }

    func testMeetingTable() {
        var g = Clearly.Recognizer()
        XCTAssertEqual(g.handle(r(.leftControlDown, 0)), [])
        XCTAssertEqual(g.ctrl, .pressed)
        XCTAssertEqual(g.handle(r(.leftControlUp, 0.2)), [.meetingToggle])
        XCTAssertEqual(g.ctrl, .idle)
        XCTAssertEqual(g.handle(r(.leftControlUp, 0.3)), [])

        _ = g.handle(r(.leftControlDown, 0.45))
        XCTAssertEqual(g.handle(r(.leftControlUp, 0.60)), [.meetingToggle])   // debounce boundary
        _ = g.handle(r(.leftControlDown, 0.90))
        XCTAssertEqual(g.handle(r(.leftControlUp, 1.45)), [])                 // >= 0.5 s
    }

    func testLatchTimeout() {
        var g = Clearly.Recognizer()
        _ = g.handle(r(.rightOptionDown, 0))
        _ = g.handle(r(.rightOptionUp, 0.05))
        XCTAssertEqual(g.tick(at: 119.9), [])
        XCTAssertEqual(g.tick(at: 120.05), [.pttSend])
        XCTAssertEqual(g.ptt, .idle)
    }
}
