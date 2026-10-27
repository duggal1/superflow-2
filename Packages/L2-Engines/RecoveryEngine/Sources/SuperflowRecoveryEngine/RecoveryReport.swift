import Foundation
import SuperflowKernel

public struct RecoveryCleaned: Sendable, Equatable {
    public var text: String
    public var state: CleanupState
    public init(text: String, state: CleanupState) {
        self.text = text
        self.state = state
    }
}

/// Injected by the app so RecoveryEngine stays free of L2 cleanup dependencies.
public typealias RecoveryCleaner = @Sendable (_ text: String) async -> RecoveryCleaned

public struct RecoveredTranscript: Sendable, Equatable, Identifiable {
    public var sessionID: SessionID
    public var text: String
    public var id: SessionID { sessionID }

    public init(sessionID: SessionID, text: String) {
        self.sessionID = sessionID
        self.text = text
    }
}

public struct RecoveryReport: Sendable, Equatable {
    public var scanned: Int
    public var recovered: Int
    public var failed: Int
    public var segmentsAdded: Int
    public var segmentsCleaned: Int
    public var samplesReplayed: Int64
    public var notices: [String]
    public var recoveredTranscripts: [RecoveredTranscript]

    public init(scanned: Int = 0, recovered: Int = 0, failed: Int = 0, segmentsAdded: Int = 0,
                segmentsCleaned: Int = 0, samplesReplayed: Int64 = 0, notices: [String] = [],
                recoveredTranscripts: [RecoveredTranscript] = []) {
        self.scanned = scanned
        self.recovered = recovered
        self.failed = failed
        self.segmentsAdded = segmentsAdded
        self.segmentsCleaned = segmentsCleaned
        self.samplesReplayed = samplesReplayed
        self.notices = notices
        self.recoveredTranscripts = recoveredTranscripts
    }

    public var hasRecoveredText: Bool { !recoveredTranscripts.isEmpty }
}
