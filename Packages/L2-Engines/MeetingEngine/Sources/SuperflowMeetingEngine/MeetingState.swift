import Foundation
import SuperflowKernel

public enum MeetingState: Sendable, Equatable {
    case idle
    case warming
    case recording
    case finalizing
    case complete(SessionID)
    case cancelled(SessionID?)
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .warming, .recording, .finalizing: true
        default: false
        }
    }
}

public enum MeetingEvent: Sendable, Equatable {
    case state(MeetingState)
    case partial(AudioSourceKind, String)
    case level(AudioSourceKind, Float)
    case notice(String)
    case finished(SessionID, MeetingDocument)
}
