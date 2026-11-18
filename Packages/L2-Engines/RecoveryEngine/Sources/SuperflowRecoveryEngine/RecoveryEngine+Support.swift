import Foundation
import SuperflowKernel

/// Named crash points. A fault injector that returns true makes the engine throw as if the process
/// had been killed at that exact point; on-disk state is then exactly what a restart would see.
public enum RecoveryStage: String, CaseIterable, Sendable, Equatable {
    case listSessions, acquireLock, readSegments, inspectJournal, createStream
    case replayStart, replayChunk, streamFinish, appendSegment, cleanSegment
    case finalize, recordFinalized, deleteJournal, sweepOrphans
}

public struct RecoveryFault: Error, Sendable, Equatable {
    public let stage: RecoveryStage
    public init(stage: RecoveryStage) { self.stage = stage }
}

public typealias RecoveryFaultInjector = @Sendable (RecoveryStage, Int) async -> Bool

public enum RecoverySupport {
    /// Millisecond transcript timestamps are the only committed watermark available in the
    /// repository, so keep the existing conversion (and its rounding behavior) for compatibility.
    public static func committedSamples(for segments: [Segment], source: AudioSourceKind) -> Int64 {
        segments.filter { $0.source == source }
            .map { Int64($0.endMs) * Int64(sampleRate) / 1000 }
            .max() ?? 0
    }

    public static func watermarks(from records: [RecoveryLedgerRecord], session: SessionID)
        -> [AudioSourceKind: Int64] {
        var result: [AudioSourceKind: Int64] = [:]
        for record in records where record.session == session.value && record.kind == .watermark {
            guard let name = record.source, let source = AudioSourceKind(rawValue: name),
                  let position = record.samplePosition else { continue }
            result[source] = max(result[source] ?? 0, position)
        }
        return result
    }

    /// ASR streams report samples relative to what they were fed. Recovery feeds from a resume
    /// position, so segment times must be shifted onto the session's absolute sample clock.
    public static func absolute(_ segment: RawSegment, baseSample: Int64) -> RawSegment {
        var adjusted = segment
        adjusted.startSample += baseSample
        adjusted.endSample += baseSample
        adjusted.words = segment.words.map { word in
            var copy = word
            copy.startMs += Int(baseSample * 1000 / Int64(sampleRate))
            copy.endMs += Int(baseSample * 1000 / Int64(sampleRate))
            return copy
        }
        return adjusted
    }

    /// A previous attempt may have committed this segment before crashing. Ignore it instead of
    /// appending a second row with the same source and time span.
    public static func isDuplicate(_ candidate: Segment, in existing: [Segment]) -> Bool {
        existing.contains { row in
            row.source == candidate.source && abs(row.startMs - candidate.startMs) <= 1
                && abs(row.endMs - candidate.endMs) <= 1
        }
    }

    public static func defaultRoot(_ component: String) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Superflow/Recovery/\(component)", isDirectory: true)
    }

    public static func eventID(_ kind: RecoveryLedgerKind, session: SessionID,
                               source: AudioSourceKind? = nil, qualifier: String = "") -> String {
        var parts = [session.value, kind.rawValue]
        if let source { parts.append(source.rawValue) }
        if !qualifier.isEmpty { parts.append(qualifier) }
        return parts.joined(separator: ":")
    }

    public static func action(_ session: SessionID, _ reason: String, _ detail: String) -> RecoveryActionRequired {
        RecoveryActionRequired(sessionID: session, reason: reason, detail: detail)
    }
}
