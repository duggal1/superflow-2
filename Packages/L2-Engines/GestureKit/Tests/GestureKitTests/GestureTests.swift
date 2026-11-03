import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowGestureKit

private let ms: UInt64 = 1_000_000

private func event(_ kind: KeyEvent.Kind, _ atMs: Int) -> KeyEvent {
    KeyEvent(kind: kind, timestampNs: UInt64(atMs) * ms)
}

final class GestureTests: XCTestCase {
    func testQuickFnTapEngagesHandsFree() {
        var g = make()
        XCTAssertEqual(g.handle(event(.fnDown, 0)), [.startSpeculative(.dictation)])
        XCTAssertEqual(g.handle(event(.fnUp, 80)), [.beginHandsFree])
        XCTAssertEqual(g.state, .handsFree)
    }

    func testExpiredCommandTapDoesNotLatchAMeeting() {
        var g = make()
        _ = g.handle(event(.rightCmdDown, 0))
        XCTAssertEqual(g.handle(event(.rightCmdUp, 80)), [.latchMeeting])
        XCTAssertEqual(g.handle(event(.rightCmdDown, 430)), [.submit(.meeting)])
    }

    func testFailedMeetingStartupDoesNotBlockNextFnPress() {
        var g = make()
        XCTAssertEqual(g.handle(event(.rightCmdDown, 0)), [.startSpeculative(.meeting)])
        XCTAssertEqual(g.tick(atNs: 600 * ms), [.holdBegan(.meeting)])
        // Simulate the backend denying microphone or system-audio access.
        g.recoverFromFailedStart(.meeting)
        XCTAssertEqual(g.state, .idle)
        XCTAssertEqual(g.handle(event(.rightCmdUp, 700)), [])
        XCTAssertEqual(g.handle(event(.fnDown, 800)), [.startSpeculative(.dictation)])
        XCTAssertEqual(g.handle(event(.fnUp, 1100)), [.submit(.dictation)])
    }

    func testFailedMeetingDoubleTapDoesNotBlockFn() {
        var g = make()
        _ = g.handle(event(.rightCmdDown, 0))
        XCTAssertEqual(g.handle(event(.rightCmdUp, 80)), [.latchMeeting])
        g.recoverFromFailedStart(.meeting)
        XCTAssertEqual(g.handle(event(.fnDown, 300)), [.startSpeculative(.dictation)])
    }

    private func make() -> GestureRecognizer { GestureRecognizer() }

    func testFnHoldIsPushToTalk() {
        var g = make()
        XCTAssertEqual(g.handle(event(.fnDown, 0)), [.startSpeculative(.dictation)])
        XCTAssertEqual(g.state, .armed)
        XCTAssertEqual(g.tick(atNs: 200 * ms), [.holdBegan(.dictation)])
        XCTAssertEqual(g.state, .pushToTalk)
        XCTAssertEqual(g.handle(event(.fnUp, 300)), [.submit(.dictation)])
        XCTAssertEqual(g.state, .idle)
    }

    func testFnShortTapEngagesHandsFree() {
        var g = make()
        XCTAssertEqual(g.handle(event(.fnDown, 0)), [.startSpeculative(.dictation)])
        XCTAssertEqual(g.handle(event(.fnUp, 80)), [.beginHandsFree])
        XCTAssertEqual(g.state, .handsFree)
        XCTAssertEqual(g.handle(event(.fnDown, 300)), [.submit(.dictation)])
        XCTAssertEqual(g.state, .idle)
    }

    /// The 10 ms tick can fire just before a short release is delivered. The
    /// release timestamp proves it was a tap, so it engages hands-free instead
    /// of submitting.
    func testLateHoldTickBeforeShortReleaseStillCountsAsTap() {
        var g = make()
        _ = g.handle(event(.fnDown, 0))
        XCTAssertEqual(g.tick(atNs: 210 * ms), [.holdBegan(.dictation)])
        XCTAssertEqual(g.state, .pushToTalk)
        XCTAssertEqual(g.handle(event(.fnUp, 120)), [.beginHandsFree])
        XCTAssertEqual(g.state, .handsFree)
    }

    func testSingleTapFnIsHandsFree() {
        var g = make()
        _ = g.handle(event(.fnDown, 0))
        XCTAssertEqual(g.handle(event(.fnUp, 80)), [.beginHandsFree])
        XCTAssertEqual(g.state, .handsFree)
        XCTAssertEqual(g.handle(event(.fnDown, 1000)), [.submit(.dictation)])
        XCTAssertEqual(g.state, .idle)
    }

    func testFnPlusOtherKeyAborts() {
        var g = make()
        _ = g.handle(event(.fnDown, 0))
        XCTAssertEqual(g.handle(event(.otherKeyDown(126), 50)), [.cancel(.dictation, .otherKey)])
        XCTAssertEqual(g.state, .idle)
    }

    func testEscapeCancelsHandsFree() {
        var g = make()
        _ = g.handle(event(.fnDown, 0))
        _ = g.handle(event(.fnUp, 50))
        XCTAssertEqual(g.state, .handsFree)
        XCTAssertEqual(g.handle(event(.escape, 300)), [.cancel(.dictation, .escape)])
        XCTAssertEqual(g.state, .idle)
    }

    func testEnterSubmitsHandsFree() {
        var g = make()
        _ = g.handle(event(.fnDown, 0))
        _ = g.handle(event(.fnUp, 50))
        XCTAssertEqual(g.state, .handsFree)
        XCTAssertEqual(g.handle(event(.enter, 400)), [.submit(.dictation)])
    }

    func testRightCommandHoldLatchesMeeting() {
        var g = make()
        XCTAssertEqual(g.handle(event(.rightCmdDown, 0)), [.startSpeculative(.meeting)])
        XCTAssertEqual(g.state, .meetingArmed)
        XCTAssertEqual(g.tick(atNs: 600 * ms), [.holdBegan(.meeting)])
        XCTAssertEqual(g.handle(event(.rightCmdUp, 700)), [.latchMeeting])
        XCTAssertEqual(g.state, .meetingLatched)
        XCTAssertEqual(g.handle(event(.rightCmdDown, 1200)), [.submit(.meeting)])
        XCTAssertEqual(g.state, .idle)
        XCTAssertEqual(g.handle(event(.rightCmdUp, 1250)), [])
    }

    func testRightCommandDoubleTapStartsMeeting() {
        var g = make()
        _ = g.handle(event(.rightCmdDown, 0))
        XCTAssertEqual(g.handle(event(.rightCmdUp, 100)), [.latchMeeting])
        XCTAssertEqual(g.state, .meetingLatched)
        XCTAssertEqual(g.handle(event(.rightCmdDown, 300)), [.submit(.meeting)])
    }

    func testRightCommandTapTimeoutCancels() {
        var g = make()
        _ = g.handle(event(.rightCmdDown, 0))
        XCTAssertEqual(g.handle(event(.rightCmdUp, 100)), [.latchMeeting])
        XCTAssertEqual(g.tick(atNs: 451 * ms), [])
    }

    func testCommandCAbortsMeetingGesture() {
        var g = make()
        _ = g.handle(event(.rightCmdDown, 0))
        XCTAssertEqual(g.handle(event(.otherKeyDown(8), 40)), [.cancel(.meeting, .otherKey)])
    }

    func testEnterSubmitsLatchedMeeting() {
        var g = make()
        _ = g.handle(event(.rightCmdDown, 0))
        _ = g.tick(atNs: 600 * ms)
        _ = g.handle(event(.rightCmdUp, 700))
        XCTAssertEqual(g.handle(event(.enter, 900)), [.submit(.meeting)])
    }

    func testFnUpAfterHoldWithoutTickSubmits() {
        var g = make()
        _ = g.handle(event(.fnDown, 0))
        XCTAssertEqual(g.handle(event(.fnUp, 250)), [.submit(.dictation)])
    }

    func testEscapeInIdleDoesNothing() {
        var g = make()
        XCTAssertEqual(g.handle(event(.escape, 0)), [])
        XCTAssertEqual(g.state, .idle)
    }

    func testIdleIgnoresKeys() {
        var g = make()
        XCTAssertEqual(g.handle(event(.enter, 0)), [])
        XCTAssertEqual(g.handle(event(.otherKeyDown(1), 0)), [])
        XCTAssertEqual(g.handle(event(.fnUp, 0)), [])
    }

    func testCustomTimings() {
        var config = GestureConfig()
        config.holdMs = 500
        config.doubleTapMs = 500
        config.meetingHoldMs = 1000
        var g = GestureRecognizer(config: config)
        _ = g.handle(event(.fnDown, 0))
        XCTAssertEqual(g.tick(atNs: 400 * ms), [])
        XCTAssertEqual(g.tick(atNs: 500 * ms), [.holdBegan(.dictation)])
    }

    func testAllStatesReachable() {
        var seen = Set<GestureState>()
        var g = make()
        seen.insert(g.state)
        _ = g.handle(event(.fnDown, 0)); seen.insert(g.state)
        _ = g.tick(atNs: 200 * ms); seen.insert(g.state)
        _ = g.handle(event(.fnUp, 300))
        _ = g.handle(event(.fnDown, 400)); seen.insert(g.state)
        _ = g.handle(event(.fnUp, 450)); seen.insert(g.state)
        _ = g.handle(event(.escape, 500))
        _ = g.handle(event(.rightCmdDown, 1000)); seen.insert(g.state)
        _ = g.tick(atNs: 1600 * ms)
        _ = g.handle(event(.rightCmdUp, 1700)); seen.insert(g.state)
        XCTAssertEqual(seen, Set(GestureState.allCases).subtracting([.awaitingSecondTap]))
    }
}
