import CoreGraphics
import Foundation
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowSessionEngine
import XCTest
@testable import SuperflowFeatureIsland

@MainActor
final class IslandViewModelTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000)
    private var model: IslandViewModel!

    override func setUp() async throws {
        now = Date(timeIntervalSince1970: 1_000)
        model = IslandViewModel(now: { [weak self] in self?.now ?? Date() })
    }

    func testHiddenUntilSessionStarts() {
        XCTAssertFalse(model.isVisible)
        model.handle(SessionEvent.state(.recording(.dictation)))
        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.phase, .listening(.dictation))
        XCTAssertEqual(model.modeLabel, "Dictation")
    }

    func testElapsedTicksFromRecordingStart() {
        model.handle(SessionEvent.state(.recording(.handsFree)))
        now = now.addingTimeInterval(12.4)
        model.tick()
        XCTAssertEqual(model.elapsedMs, 12_400)
        XCTAssertEqual(model.elapsedLabel, "0:12")
    }

    func testPartialsCountWordsAndKeepRecentLevels() {
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.handle(SessionEvent.partial("hello there world"))
        XCTAssertEqual(model.wordCount, 3)
        for index in 0..<60 {
            now = now.addingTimeInterval(0.05)
            model.handle(SessionEvent.level(Float(index) / 60))
        }
        XCTAssertEqual(model.levels.count, 48)
        XCTAssertEqual(model.levels.last ?? 0, 59.0 / 60.0, accuracy: 0.001)
    }

    func testLevelsAreThrottledToThirtyFramesPerSecond() {
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.handle(SessionEvent.level(0.4))
        model.handle(SessionEvent.level(0.9))
        XCTAssertEqual(model.levels.count, 1)
        now = now.addingTimeInterval(0.04)
        model.handle(SessionEvent.level(0.9))
        XCTAssertEqual(model.levels.count, 2)
    }

    func testCompletionHidesAfterBriefConfirmation() {
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.handle(SessionEvent.state(.complete(SessionID("s"))))
        XCTAssertEqual(model.phase, .complete)
        now = now.addingTimeInterval(1.0)
        model.tick()
        XCTAssertTrue(model.isVisible)
        now = now.addingTimeInterval(1.0)
        model.tick()
        XCTAssertFalse(model.isVisible)
    }

    func testCancelResetsEverything() {
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.handle(SessionEvent.partial("unfinished"))
        model.handle(SessionEvent.state(.cancelled(SessionID("s"))))
        XCTAssertFalse(model.isVisible)
        XCTAssertEqual(model.partial, "")
        XCTAssertEqual(model.elapsedMs, 0)
    }

    func testMeetingTracksBothSources() {
        model.handle(MeetingEvent.state(.recording))
        model.handle(MeetingEvent.partial(.mic, "my update"))
        model.handle(MeetingEvent.partial(.system, "their reply"))
        XCTAssertEqual(model.phase, .listening(.meeting))
        XCTAssertEqual(model.partial, "my update")
        XCTAssertEqual(model.systemPartial, "their reply")
        XCTAssertEqual(model.wordCount, 4)
    }

    func testNoticeSurvivesUntilNextSession() {
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.handle(SessionEvent.notice("System audio was lost."))
        XCTAssertEqual(model.notice, "System audio was lost.")
        model.handle(SessionEvent.state(.recording(.handsFree)))
        XCTAssertNil(model.notice)
    }

    func testExpansionOnlyWhenVisible() {
        model.toggleExpanded()
        XCTAssertFalse(model.isExpanded)
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.toggleExpanded()
        XCTAssertTrue(model.isExpanded)
    }

    func testIdlePillIsOptInAndDoesNotExpand() {
        XCTAssertFalse(model.isVisible)
        model.setShowIdlePill(true)
        XCTAssertTrue(model.isVisible)
        XCTAssertTrue(model.isIdle)
        model.toggleExpanded()
        XCTAssertFalse(model.isExpanded, "the idle pill is not an expandable session")

        model.handle(SessionEvent.state(.recording(.dictation)))
        model.setShowIdlePill(false)
        XCTAssertTrue(model.isVisible, "a live session stays visible without the idle pill")
        model.handle(SessionEvent.state(.cancelled(SessionID("s"))))
        XCTAssertFalse(model.isVisible)
    }

    func testDegradedPhaseKeepsTheSessionActive() {
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.degrade("System audio was lost.")
        XCTAssertEqual(model.phase, .degraded("System audio was lost."))
        XCTAssertTrue(model.phase.isActive)
        XCTAssertTrue(model.isDegraded)
        XCTAssertEqual(model.modeLabel, "Needs attention")
        XCTAssertEqual(model.notice, "System audio was lost.")
        XCTAssertTrue(model.isVisible)
    }

    func testNoticeMarksActiveSessionAsDegraded() {
        model.handle(SessionEvent.state(.recording(.dictation)))
        model.handle(SessionEvent.notice("Basic cleanup only."))
        XCTAssertEqual(model.phase, .listening(.dictation), "the session keeps running")
        XCTAssertTrue(model.isDegraded)
    }

    func testIslandMetricsMatchThePanel() {
        XCTAssertEqual(IslandMetrics.compactWidth, 280)
        XCTAssertEqual(IslandMetrics.expandedWidth, 460)
        XCTAssertEqual(IslandMetrics.compactHeight, 60)
        XCTAssertEqual(IslandMetrics.expandedHeight, 160)
    }

    func testDragPolicyUsesAFourPointThreshold() {
        XCTAssertEqual(IslandDragPolicy.threshold, 4)
        XCTAssertTrue(IslandDragPolicy.isClick(.zero))
        XCTAssertTrue(IslandDragPolicy.isClick(CGSize(width: 3, height: 0)))
        XCTAssertTrue(IslandDragPolicy.isClick(CGSize(width: 2, height: 2)))
        XCTAssertTrue(IslandDragPolicy.isDrag(CGSize(width: 4, height: 0)))
        XCTAssertTrue(IslandDragPolicy.isDrag(CGSize(width: 0, height: 5)))
        XCTAssertTrue(IslandDragPolicy.isDrag(CGSize(width: 3, height: 3)))
        XCTAssertFalse(IslandDragPolicy.isDrag(CGSize(width: 2, height: 2)))
    }
}
