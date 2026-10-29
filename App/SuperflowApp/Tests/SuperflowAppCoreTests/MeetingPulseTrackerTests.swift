import SuperflowKernel
import SuperflowMeetingEngine
import XCTest
@testable import SuperflowAppCore

final class MeetingPulseTrackerTests: XCTestCase {
    private func document(_ turns: [MeetingTurn]) -> MeetingDocument {
        MeetingDocument(sessionID: SessionID(), title: "Fixture", startedAt: .now,
                        endedAt: nil, durationMs: 4000, speakers: [], turns: turns)
    }

    private func turn(_ index: Int, text: String = "Two words") -> MeetingTurn {
        MeetingTurn(index: index, speakerID: "self", speakerName: "You",
                    startMs: index * 2000, endMs: index * 2000 + 1000,
                    text: text, rawText: text, source: .mic)
    }

    func testRepeatedPulseDoesNotDoubleCountAndCleanupCanReviseWords() {
        var tracker = MeetingPulseTracker()
        _ = tracker.update(document([turn(0)]), seconds: 2)
        let repeated = tracker.update(document([turn(0)]), seconds: 2)
        XCTAssertEqual(repeated.words, 2)
        XCTAssertEqual(repeated.speakers.first?.seconds, 1)
        let revised = tracker.update(document([turn(0, text: "Three cleaned words")]), seconds: 2)
        XCTAssertEqual(revised.words, 3)
        XCTAssertEqual(revised.speakers.first?.seconds, 1)
    }

    func testRotatingEngineWindowKeepsTotalsAndSilence() {
        var tracker = MeetingPulseTracker()
        _ = tracker.update(document([turn(0)]), seconds: 2)
        let pulse = tracker.update(document([turn(1)]), seconds: 6)
        XCTAssertEqual(pulse.words, 4)
        XCTAssertEqual(pulse.speakers.first?.seconds, 2)
        XCTAssertEqual(pulse.slices, [0, 0, -1])
        XCTAssertNil(pulse.current)
    }

    func testLongMeetingKeepsTimelineBounded() {
        var tracker = MeetingPulseTracker()
        let pulse = tracker.update(document([turn(0)]), seconds: 36_000)
        XCTAssertLessThanOrEqual(pulse.slices.count, 1800)
        XCTAssertGreaterThan(pulse.slice, 2)
    }
}
