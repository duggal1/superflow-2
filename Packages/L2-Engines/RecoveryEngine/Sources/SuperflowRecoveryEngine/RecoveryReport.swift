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

/// A journal that was removed after its transcript was verified. Recorded so the report is truthful
/// about data that recovery itself discarded instead of hiding the deletion.
public struct RecoveryDiscarded: Sendable, Equatable, Identifiable {
    public var sessionID: SessionID
    public var reason: String
    public var samples: Int64
    public var id: SessionID { sessionID }
    public init(sessionID: SessionID, reason: String, samples: Int64) {
        self.sessionID = sessionID
        self.reason = reason
        self.samples = samples
    }
}

/// Something recovery deliberately did not fix. The data is retained; a human must decide.
public struct RecoveryActionRequired: Sendable, Equatable, Identifiable {
    public var sessionID: SessionID
    public var reason: String
    public var detail: String
    public var id: SessionID { sessionID }
    public init(sessionID: SessionID, reason: String, detail: String) {
        self.sessionID = sessionID
        self.reason = reason
        self.detail = detail
    }
}

/// An explicit lost interval on one journal lane. Recovery never silently bridges missing audio
/// with fabricated continuity: the interval is reported and recorded so a human can decide.
public struct RecoveryGap: Sendable, Equatable, Identifiable {
    public var sessionID: SessionID
    public var source: AudioSourceKind
    public var startSample: Int64
    public var endSample: Int64
    public var reason: String

    public var id: String { "\(sessionID.value):\(source.rawValue):\(startSample)" }
    public var samples: Int64 { max(0, endSample - startSample) }

    public init(sessionID: SessionID, source: AudioSourceKind, startSample: Int64,
                endSample: Int64, reason: String) {
        self.sessionID = sessionID
        self.source = source
        self.startSample = startSample
        self.endSample = endSample
        self.reason = reason
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

    /// New, additive fields. Existing callers keep compiling unchanged.
    public var discarded: [RecoveryDiscarded]
    public var needsUserAction: [RecoveryActionRequired]
    public var skippedBusy: Int
    public var integrity: RecoveryLedgerIntegrity
    public var quarantinedFiles: [String]

    /// Lanes that could not be recovered. The healthy lanes still recover and finalize; these are
    /// named explicitly rather than silently dropped. Empty means no lane degraded.
    public var degradedSources: [AudioSourceKind]
    /// Journal discontinuities that were observed instead of being papered over with fake audio.
    public var gaps: [RecoveryGap]

    public init(scanned: Int = 0, recovered: Int = 0, failed: Int = 0, segmentsAdded: Int = 0,
                segmentsCleaned: Int = 0, samplesReplayed: Int64 = 0, notices: [String] = [],
                recoveredTranscripts: [RecoveredTranscript] = [], discarded: [RecoveryDiscarded] = [],
                needsUserAction: [RecoveryActionRequired] = [], skippedBusy: Int = 0,
                integrity: RecoveryLedgerIntegrity = RecoveryLedgerIntegrity(),
                quarantinedFiles: [String] = [], degradedSources: [AudioSourceKind] = [],
                gaps: [RecoveryGap] = []) {
        self.scanned = scanned
        self.recovered = recovered
        self.failed = failed
        self.segmentsAdded = segmentsAdded
        self.segmentsCleaned = segmentsCleaned
        self.samplesReplayed = samplesReplayed
        self.notices = notices
        self.recoveredTranscripts = recoveredTranscripts
        self.discarded = discarded
        self.needsUserAction = needsUserAction
        self.skippedBusy = skippedBusy
        self.integrity = integrity
        self.quarantinedFiles = quarantinedFiles
        self.degradedSources = degradedSources
        self.gaps = gaps
    }

    public var hasRecoveredText: Bool { !recoveredTranscripts.isEmpty }
    /// True only when nothing needs a human decision and no ledger record was damaged.
    public var isClean: Bool {
        failed == 0 && needsUserAction.isEmpty && skippedBusy == 0 && integrity.isClean
    }
}
