import XCTest
@testable import SuperflowFeatureIsland

@MainActor
final class IslandNoticeTests: XCTestCase {
    private struct Feed: IslandFeed {
        var events: AsyncStream<IslandEvent> { AsyncStream { $0.finish() } }
        var levels: AsyncStream<Float> { AsyncStream { $0.finish() } }
        var storesTranscripts: Bool { true }
        func lastTranscript() -> IslandTranscript? { nil }
    }

    private func model() -> IslandModel {
        IslandModel(feed: Feed(), geometry: NotchGeometry(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeTop: 38, leftWidth: 704, rightWidth: 704, scale: 2))
    }

    func testMilestoneWaitsUntilCaptureEnds() async throws {
        let model = model()
        let notice = IslandNotice.milestone(words: 1000)
        model.send(.holdBegan(nil))
        model.send(.notice(notice))
        XCTAssertEqual(model.phase, .listening)
        model.send(.cancelled)
        XCTAssertEqual(model.phase, .idle)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(model.phase, .notice(notice))
        model.send(.dismissed)
    }

    func testPassiveNoticesNeverReplaceLiveModesOrCards() {
        let transcript = IslandTranscript(text: "Cleaned", bundleID: nil, appName: nil, date: .now, words: 1)
        let phases: [IslandPhase] = [.listening, .handsFree, .meeting, .meetingPanel, .processing,
                                    .landed(words: 1), .failed(transcript), .recent(nil), .history]
        for phase in phases {
            for notice in [IslandNotice.milestone(words: 1000), .streak(days: 7), .modelReady("S1-mini")] {
                XCTAssertEqual(IslandReducer.reduce(phase, .notice(notice)), phase)
            }
        }
    }

    func testStaleNoticeIsIgnored() {
        let model = model()
        model.notify(IslandNotice(kind: .milestone, title: "Old milestone", detail: "",
                                  postedAt: Date().addingTimeInterval(-121)))
        XCTAssertEqual(model.phase, .idle)
    }

    func testNoticeThatExpiresInQueueNeverAppears() async throws {
        let model = model()
        model.send(.holdBegan(nil))
        model.notify(IslandNotice(kind: .milestone, title: "Expiring milestone", detail: "",
                                  postedAt: Date().addingTimeInterval(-119.8)))
        model.send(.cancelled)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(model.phase, .idle)
    }

    func testPastedWordCountDoesNotInventAMilestone() async throws {
        let model = model()
        model.send(.holdBegan(nil))
        model.send(.landed(words: 1000))
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertEqual(model.phase, .idle)
    }

    func testCollapsingMeetingDoesNotReplayHints() {
        let model = model()
        model.send(.meetingBegan(nil))
        XCTAssertTrue(model.hint)
        model.send(.notchClicked)
        model.send(.notchClicked)
        XCTAssertEqual(model.phase, .meeting)
        XCTAssertFalse(model.hint)
        model.send(.cancelled)
    }

    func testHidingLiveTextClearsTheRetainedPartial() {
        let model = model()
        model.configure(IslandPrefs(liveText: true))
        model.live = LiveText(text: "A partial")
        model.configure(IslandPrefs(liveText: false))
        XCTAssertEqual(model.live, .empty)
    }
}
