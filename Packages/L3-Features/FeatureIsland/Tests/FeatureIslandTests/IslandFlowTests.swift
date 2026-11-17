import SwiftUI
import XCTest
@testable import SuperflowFeatureIsland

private struct EmptyFeed: IslandFeed {
    var events: AsyncStream<IslandEvent> { AsyncStream { $0.finish() } }
    var levels: AsyncStream<Float> { AsyncStream { $0.finish() } }
    func lastTranscript() -> IslandTranscript? { nil }
    var storesTranscripts: Bool { true }
}

/// The pure machine: every state, every transition and every guard, exercised
/// without AppKit or a view. These are the acceptance tests for the rebuild.
final class IslandFlowTests: XCTestCase {
    private let allStates: [IslandFlowState] = [
        .collapsed,
        .compose(draft: "draft"),
        .listening(target: "TextEdit"),
        .thinking(query: "why"),
        .answer(text: "answer", streaming: true),
        .answer(text: "answer", streaming: false),
        .meetingLive(elapsed: 42),
        .meetingEnded(suggestions: ["one", "two"]),
        .undo(text: "A long cancelled transcript"),
        .history(count: 5),
        .settings(theme: "Journal"),
        .error(message: "failed"),
        .permission(kind: .microphone),
        .permission(kind: .screenRecording),
        .permission(kind: .inputMonitoring),
    ]

    private let allEvents: [IslandFlowEvent] = [
        .entered, .exited, .collapsed, .compose, .draftChanged("x"),
        .startedListening(nil), .stoppedListening, .submitted("q"), .thinking("q"),
        .streamed("a"), .answered("a"), .meetingStarted, .meetingTicked(9),
        .meetingEnded(["s"]), .asked("q"), .openedHistory(count: 3),
        .openedSettings(theme: "Sales"), .themeChanged("Custom"),
        .permissionRequired(.microphone), .failed("boom"), .recovered, .dismissed,
    ]

    // MARK: primary flow

    func testCollapsedToComposeToListeningToThinkingToAnswer() {
        var s: IslandFlowState = .collapsed
        s = IslandFlowReducer.reduce(s, .compose)
        XCTAssertEqual(s, .compose(draft: ""))
        s = IslandFlowReducer.reduce(s, .draftChanged("summarize"))
        XCTAssertEqual(s, .compose(draft: "summarize"))
        s = IslandFlowReducer.reduce(s, .startedListening("TextEdit"))
        XCTAssertEqual(s, .listening(target: "TextEdit"))
        s = IslandFlowReducer.reduce(s, .submitted("summarize"))
        XCTAssertEqual(s, .thinking(query: "summarize"))
        s = IslandFlowReducer.reduce(s, .streamed("sum"))
        XCTAssertEqual(s, .answer(text: "sum", streaming: true))
        s = IslandFlowReducer.reduce(s, .streamed("summary"))
        XCTAssertEqual(s, .answer(text: "summary", streaming: true))
        s = IslandFlowReducer.reduce(s, .answered("summary"))
        XCTAssertEqual(s, .answer(text: "summary", streaming: false))
    }

    func testListeningCancellationReturnsToCompose() {
        let s = IslandFlowReducer.reduce(.listening(target: nil), .stoppedListening)
        XCTAssertEqual(s, .compose(draft: ""))
    }

    // MARK: meeting flow

    func testCollapsedToMeetingLiveToMeetingEndedToAnswer() {
        var s = IslandFlowReducer.reduce(.collapsed, .meetingStarted)
        XCTAssertEqual(s, .meetingLive(elapsed: 0))
        s = IslandFlowReducer.reduce(s, .meetingTicked(75))
        XCTAssertEqual(s, .meetingLive(elapsed: 75))
        s = IslandFlowReducer.reduce(s, .meetingEnded(["what did we decide?", "next steps?"]))
        XCTAssertEqual(s, .meetingEnded(suggestions: ["what did we decide?", "next steps?"]))
        s = IslandFlowReducer.reduce(s, .asked("what did we decide?"))
        XCTAssertEqual(s, .thinking(query: "what did we decide?"))
        s = IslandFlowReducer.reduce(s, .answered("We decided to ship."))
        XCTAssertEqual(s, .answer(text: "We decided to ship.", streaming: false))
    }

    // MARK: any → overlay states

    func testAnyStateOpensHistory() {
        for state in allStates {
            let next = IslandFlowReducer.reduce(state, .openedHistory(count: 7))
            XCTAssertEqual(next, .history(count: 7), "history must be reachable from \(state)")
        }
    }

    func testAnyStateOpensSettings() {
        for state in allStates {
            let next = IslandFlowReducer.reduce(state, .openedSettings(theme: "Coding interview"))
            XCTAssertEqual(next, .settings(theme: "Coding interview"), "settings must be reachable from \(state)")
        }
    }

    func testAnyStateEntersErrorAndPermission() {
        for state in allStates {
            XCTAssertEqual(IslandFlowReducer.reduce(state, .failed("nope")), .error(message: "nope"))
            XCTAssertEqual(IslandFlowReducer.reduce(state, .permissionRequired(.screenRecording)),
                           .permission(kind: .screenRecording))
        }
    }

    func testAnyStateDismissesOrRecoversToCollapsed() {
        for state in allStates {
            XCTAssertEqual(IslandFlowReducer.reduce(state, .dismissed), .collapsed)
            XCTAssertEqual(IslandFlowReducer.reduce(state, .recovered), .collapsed)
            XCTAssertEqual(IslandFlowReducer.reduce(state, .collapsed), .collapsed)
        }
    }

    // MARK: entry / exit variants

    func testEntryAndExitPreserveEveryState() {
        for state in allStates {
            XCTAssertEqual(IslandFlowReducer.reduce(state, .entered), state)
            XCTAssertEqual(IslandFlowReducer.reduce(state, .exited), state)
        }
    }

    // MARK: guarded transitions

    func testDraftOnlyChangesInCompose() {
        XCTAssertEqual(IslandFlowReducer.reduce(.compose(draft: "a"), .draftChanged("ab")),
                       .compose(draft: "ab"))
        for state in allStates {
            if case .compose = state { continue }
            XCTAssertEqual(IslandFlowReducer.reduce(state, .draftChanged("ab")), state)
        }
    }

    func testMeetingTickOnlyChangesALiveMeeting() {
        XCTAssertEqual(IslandFlowReducer.reduce(.meetingLive(elapsed: 1), .meetingTicked(2)),
                       .meetingLive(elapsed: 2))
        for state in allStates {
            if case .meetingLive = state { continue }
            XCTAssertEqual(IslandFlowReducer.reduce(state, .meetingTicked(2)), state)
        }
    }

    func testStoppedListeningOnlyChangesListening() {
        for state in allStates {
            if case .listening = state { continue }
            XCTAssertEqual(IslandFlowReducer.reduce(state, .stoppedListening), state)
        }
    }

    func testThemeOnlyChangesInSettings() {
        XCTAssertEqual(IslandFlowReducer.reduce(.settings(theme: "Normal"), .themeChanged("Journal")),
                       .settings(theme: "Journal"))
        for state in allStates where state != .settings(theme: "Normal") {
            XCTAssertEqual(IslandFlowReducer.reduce(state, .themeChanged("Journal")), state)
        }
    }

    // MARK: totality / determinism

    func testReducerIsTotalAndDeterministic() {
        for state in allStates {
            for event in allEvents {
                let a = IslandFlowReducer.reduce(state, event)
                let b = IslandFlowReducer.reduce(state, event)
                XCTAssertEqual(a, b, "nondeterministic for \(state) + \(event)")
            }
        }
    }

    func testEveryStageIDIsUnique() {
        let ids = Set(allStates.map(\.stageID))
        // answer streaming/final share a stage; all three permission kinds share
        // one. Everything else owns its stage so cross-dissolves are correct.
        XCTAssertEqual(ids.count, 12)
        XCTAssertEqual(IslandFlowState.answer(text: "a", streaming: true).stageID,
                       IslandFlowState.answer(text: "a", streaming: false).stageID)
        XCTAssertEqual(IslandFlowState.permission(kind: .microphone).stageID,
                       IslandFlowState.permission(kind: .inputMonitoring).stageID)
    }

    /// The app-side Intelligence seam injects hosted content without FeatureIsland
    /// importing another L3 module. This asserts the closure is stored and invoked
    /// with the live flow state.
    @MainActor
    func testHostedIntelligenceClosureIsWiredThroughTheModel() {
        let model = IslandModel(feed: EmptyFeed(), geometry:
            NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                          safeTop: 32, leftWidth: 620, rightWidth: 620, scale: 2))
        var seen: IslandFlowState?
        model.intelligenceContent = { state in
            seen = state
            return AnyView(EmptyView())
        }
        XCTAssertNotNil(model.intelligenceContent)
        _ = model.intelligenceContent?(.compose(draft: ""))
        XCTAssertEqual(seen, .compose(draft: ""))
    }

    @MainActor
    func testStoreAppliesEventsInOrder() {
        let store = IslandFlowStore()
        XCTAssertEqual(store.state, .collapsed)
        store.apply(.compose)
        store.apply(.submitted("q"))
        store.apply(.answered("a"))
        XCTAssertEqual(store.state, .answer(text: "a", streaming: false))
        store.replace(.permission(kind: .microphone))
        XCTAssertEqual(store.state, .permission(kind: .microphone))
        store.apply(.recovered)
        XCTAssertEqual(store.state, .collapsed)
    }
}
