import Foundation
import Observation

/// A permission the Island can be waiting on. These are UI states only: the
/// backend owns the actual authorization calls.
public enum IslandPermission: Equatable, Sendable {
    case microphone
    case screenRecording
    case inputMonitoring
}

/// The rebuilt Island's one logical phase. It is a value type with no AppKit, no
/// observation and no side effects; the reducer is the only thing that changes
/// it. Entry/exit are expressed as events (`.entered`/`.exited`) so presence
/// never forks the state; error and permission are real states so they render
/// completely under Reduce Motion.
public enum IslandFlowState: Equatable, Sendable {
    case collapsed
    case compose(draft: String)
    case listening(target: String?)
    case thinking(query: String)
    case answer(text: String, streaming: Bool)
    case meetingLive(elapsed: Int)
    case meetingEnded(suggestions: [String])
    case undo(text: String)
    case history(count: Int)
    case settings(theme: String)
    case error(message: String)
    case permission(kind: IslandPermission)
}

public enum IslandFlowEvent: Equatable, Sendable {
    /// Presence variants: the silhouette entering or leaving the screen. They
    /// never change the logical phase, only the geometry that reveals it.
    case entered
    case exited

    case collapsed
    case compose
    case draftChanged(String)
    case startedListening(String?)
    case stoppedListening

    case submitted(String)
    case thinking(String)
    case streamed(String)
    case answered(String)

    case meetingStarted
    case meetingTicked(Int)
    case meetingEnded([String])
    case asked(String)
    case undoOffered(String)

    case openedHistory(count: Int)
    case openedSettings(theme: String)
    case themeChanged(String)

    case permissionRequired(IslandPermission)
    case failed(String)
    case recovered
    case dismissed
}

/// The whole state machine. Total, deterministic and pure: given a state and an
/// event there is exactly one next state, and no event depends on the outside
/// world. That is what makes every transition directly unit-testable.
public enum IslandFlowReducer {
    public static func reduce(_ state: IslandFlowState, _ event: IslandFlowEvent) -> IslandFlowState {
        switch event {
        case .entered, .exited:
            return state

        case .collapsed, .dismissed, .recovered:
            return .collapsed

        case .compose:
            return .compose(draft: "")

        case .draftChanged(let text):
            guard case .compose = state else { return state }
            return .compose(draft: text)

        case .startedListening(let target):
            return .listening(target: target)

        case .stoppedListening:
            guard case .listening = state else { return state }
            return .compose(draft: "")

        case .submitted(let query), .thinking(let query), .asked(let query):
            return .thinking(query: query)

        case .streamed(let text):
            return .answer(text: text, streaming: true)

        case .answered(let text):
            return .answer(text: text, streaming: false)

        case .meetingStarted:
            return .meetingLive(elapsed: 0)

        case .meetingTicked(let seconds):
            guard case .meetingLive = state else { return state }
            return .meetingLive(elapsed: seconds)

        case .meetingEnded(let suggestions):
            return .meetingEnded(suggestions: suggestions)

        case .undoOffered(let text):
            return .undo(text: text)

        case .openedHistory(let count):
            return .history(count: count)

        case .openedSettings(let theme):
            return .settings(theme: theme)

        case .themeChanged(let theme):
            guard case .settings = state else { return state }
            return .settings(theme: theme)

        case .permissionRequired(let kind):
            return .permission(kind: kind)

        case .failed(let message):
            return .error(message: message)
        }
    }
}

public extension IslandFlowState {
    /// A new stage cross-dissolves its content; the same stage morphs in place.
    var stageID: String {
        switch self {
        case .collapsed: "collapsed"
        case .compose: "compose"
        case .listening: "listening"
        case .thinking: "thinking"
        case .answer: "answer"
        case .meetingLive: "meetingLive"
        case .meetingEnded: "meetingEnded"
        case .undo: "undo"
        case .history: "history"
        case .settings: "settings"
        case .error: "error"
        case .permission: "permission"
        }
    }
}

/// A thin observable holder around the pure reducer. Views read `state` and
/// call `apply`; the reducer itself remains AppKit-free and trivially testable.
@MainActor
@Observable
public final class IslandFlowStore {
    public private(set) var state: IslandFlowState

    public init(_ state: IslandFlowState = .collapsed) {
        self.state = state
    }

    public func apply(_ event: IslandFlowEvent) {
        state = IslandFlowReducer.reduce(state, event)
    }

    /// Adoption seam: the existing backend model pushes an authoritative phase
    /// in here without forking the reducer's transition rules.
    public func replace(_ state: IslandFlowState) {
        self.state = state
    }
}
