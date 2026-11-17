import XCTest
import SuperflowClearlyInput

/// Verifies that the gesture outputs reach the existing-backend action hooks,
/// and that state is not double-fired. Fully headless: actions are recorded in
/// an actor, nothing reaches an event tap or the UI.
final class ClearlyInputSessionTests: XCTestCase {

    private actor Recorder {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
        func snapshot() -> [String] { events }
    }

    private func makeCoordinator(_ recorder: Recorder) -> SessionCoordinator {
        let actions = IntelligenceSessionActions(
            pttBegan: { await recorder.record("pttBegan") },
            pttWaveform: { await recorder.record("waveform") },
            pttCancelled: { await recorder.record("pttCancelled") },
            pttLatched: { await recorder.record("pttLatched") },
            pttSend: { await recorder.record("pttSend") },
            meetingToggle: { await recorder.record($0 ? "meetingStart" : "meetingEnd") },
            suppressQuestionDetector: { await recorder.record($0 ? "suppressOn" : "suppressOff") },
            secureInputChanged: { await recorder.record($0 ? "securePaused" : "secureResumed") }
        )
        return SessionCoordinator(actions: actions, clock: { 0 }, waveformDelay: 0)
    }

    func testHoldSend_wiresBeganWaveformAndSend() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(recorder)
        await coordinator.handle(Clearly.RawEvent(.rightOptionDown, at: 0))
        try? await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.handle(Clearly.RawEvent(.rightOptionUp, at: 1))
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["pttBegan", "waveform", "pttSend"])
        let state = await coordinator.state
        XCTAssertFalse(state.pttActive)
    }

    func testInterference_wiresCancel_andNoWaveform() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(recorder)
        await coordinator.handle(Clearly.RawEvent(.rightOptionDown, at: 0))
        await coordinator.handle(Clearly.RawEvent(.interference, at: 0.01))
        // Let the delayed waveform task run; it must have been cancelled.
        try? await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.handle(Clearly.RawEvent(.rightOptionUp, at: 1))
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["pttBegan", "pttCancelled"])
    }

    func testTapLatch_thenSend() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(recorder)
        await coordinator.handle(Clearly.RawEvent(.rightOptionDown, at: 0))
        await coordinator.handle(Clearly.RawEvent(.rightOptionUp, at: 0.05))
        try? await Task.sleep(nanoseconds: 20_000_000)
        let latched = await coordinator.state
        XCTAssertTrue(latched.pttLatched)
        await coordinator.handle(Clearly.RawEvent(.rightOptionDown, at: 1))
        await coordinator.handle(Clearly.RawEvent(.rightOptionUp, at: 1.1))
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["pttBegan", "waveform", "pttLatched", "pttSend"])
    }

    func testMeetingToggle_startsAndEnds() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(recorder)
        await coordinator.handle(Clearly.RawEvent(.leftControlDown, at: 0))
        await coordinator.handle(Clearly.RawEvent(.leftControlUp, at: 0.1))
        let started = await coordinator.state
        XCTAssertTrue(started.meetingLive)
        await coordinator.handle(Clearly.RawEvent(.leftControlDown, at: 1))
        await coordinator.handle(Clearly.RawEvent(.leftControlUp, at: 1.1))
        let ended = await coordinator.state
        XCTAssertFalse(ended.meetingLive)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["meetingStart", "meetingEnd"])
    }

    func testPTTinsideMeeting_suppressesQuestionDetector() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(recorder)
        await coordinator.handle(Clearly.RawEvent(.leftControlDown, at: 0))
        await coordinator.handle(Clearly.RawEvent(.leftControlUp, at: 0.1))
        await coordinator.handle(Clearly.RawEvent(.rightOptionDown, at: 0.5))
        try? await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.handle(Clearly.RawEvent(.rightOptionUp, at: 1.0))
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["meetingStart", "suppressOn", "pttBegan", "waveform", "suppressOff", "pttSend"])
    }

    func testSecureInputPause_isSurfaced() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(recorder)
        await coordinator.secureInputChanged(true)
        await coordinator.secureInputChanged(false)
        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["securePaused", "secureResumed"])
    }
}
