import Foundation
import SuperflowKernel
import SuperflowPorts

public enum SessionMode: String, Sendable, Equatable, CaseIterable {
    case dictation
    case handsFree
    public var label: String { self == .dictation ? "Dictation" : "Hands-free" }
}

public enum SessionState: Sendable, Equatable {
    case idle
    case warming
    case recording(SessionMode)
    case finalizing
    case inserting
    case complete(SessionID)
    case cancelled(SessionID?)
    case failed(SessionID?, String)

    public var isActive: Bool {
        switch self {
        case .warming, .recording, .finalizing, .inserting: true
        default: false
        }
    }

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .warming: "Warming"
        case .recording(let mode): mode.label
        case .finalizing: "Finalizing"
        case .inserting: "Inserting"
        case .complete: "Complete"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
}

public enum SessionEvent: Sendable, Equatable {
    case state(SessionState)
    case partial(String)
    case level(Float)
    case progress(Double)
    case notice(String)
    case inserted(InsertionOutcome)
    case finished(SessionID, SessionStatus)
}

public struct SessionOutcome: Sendable, Equatable {
    public var sessionID: SessionID
    public var text: String
    public var wordCount: Int
    public var cleanupState: CleanupState
    public var insertion: InsertionOutcome?
    public init(sessionID: SessionID, text: String, wordCount: Int,
                cleanupState: CleanupState, insertion: InsertionOutcome?) {
        self.sessionID = sessionID
        self.text = text
        self.wordCount = wordCount
        self.cleanupState = cleanupState
        self.insertion = insertion
    }
}
