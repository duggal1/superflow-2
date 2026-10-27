import Foundation
import SuperflowKernel

public enum GestureState: String, Sendable, Equatable, CaseIterable {
    case idle
    case armed
    case pushToTalk
    case awaitingSecondTap
    case handsFree
    case meetingArmed
    case meetingLatched
}

public enum GestureCancelReason: String, Sendable, Equatable {
    case escape
    case otherKey
    case secondTapTimeout
}

public enum GestureAction: Sendable, Equatable {
    /// Recording starts speculatively on the first key down; no words are lost.
    case startSpeculative(SessionKind)
    /// The hold threshold was crossed while the key is still down.
    case holdBegan(SessionKind)
    case beginHandsFree
    case latchMeeting
    case submit(SessionKind)
    case cancel(SessionKind, GestureCancelReason)
}
