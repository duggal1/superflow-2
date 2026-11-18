import Foundation
import SuperflowKernel

/// A versioned, storage-agnostic projection of one session. `schemaVersion`
/// lets a consumer ignore unknown fields and detect an incompatible change,
/// matching the read-only JSON contract used by Hex's transcript CLI. All
/// fields are local — no account, device identifier, or network state is
/// exported.
public struct TranscriptExportDocument: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var metadata: Metadata
    public var speakers: [Speaker]
    public var segments: [Segment]

    public struct Metadata: Sendable, Codable, Equatable {
        public var sessionID: String
        public var kind: String
        public var title: String?
        public var status: String
        public var startedAtMs: Int64
        public var endedAtMs: Int64?
        public var durationMs: Int
        public var wordCount: Int
        public var modelProfile: String
    }

    public struct Speaker: Sendable, Codable, Equatable {
        public var id: String
        public var label: String
        public var isSelf: Bool
    }

    public struct Segment: Sendable, Codable, Equatable {
        public var start: Int
        public var end: Int
        public var source: String
        public var speaker: String?
        public var raw: String
        public var final: String
    }
}

/// Pure rendering from domain models to the versioned document and to Markdown.
/// Keeping this free of SQLite makes the export contract directly testable.
public enum TranscriptExporter {
    public static let currentSchemaVersion = 1

    public static func document(session: SessionRecord,
                                speakers: [SpeakerRecord],
                                segments: [Segment]) -> TranscriptExportDocument {
        TranscriptExportDocument(
            schemaVersion: currentSchemaVersion,
            metadata: .init(
                sessionID: session.id.value,
                kind: session.kind.rawValue,
                title: session.title,
                status: session.status.rawValue,
                startedAtMs: Int64((session.startedAt.timeIntervalSince1970 * 1_000).rounded()),
                endedAtMs: session.endedAt.map {
                    Int64(($0.timeIntervalSince1970 * 1_000).rounded())
                },
                durationMs: session.durationMs,
                wordCount: session.wordCount,
                modelProfile: session.modelProfile),
            speakers: speakers.map {
                .init(id: $0.id, label: $0.label, isSelf: $0.isSelf)
            },
            segments: segments.map { segment in
                .init(start: segment.startMs, end: segment.endMs,
                      source: segment.source.rawValue, speaker: segment.speakerID,
                      raw: segment.rawText, final: segment.bestText)
            })
    }

    public static func markdown(_ document: TranscriptExportDocument) -> String {
        let title: String
        if let stored = document.metadata.title, !stored.isEmpty {
            title = stored
        } else {
            title = "Transcript \(document.metadata.sessionID)"
        }

        var labels: [String: String] = [:]
        for speaker in document.speakers { labels[speaker.id] = speaker.label }

        var lines: [String] = ["# \(title)", ""]
        lines.append("- Session: \(document.metadata.sessionID)")
        lines.append("- Kind: \(document.metadata.kind)")
        lines.append("- Status: \(document.metadata.status)")
        lines.append("- Started: \(document.metadata.startedAtMs)")
        lines.append("- Duration: \(document.metadata.durationMs) ms")
        lines.append("- Words: \(document.metadata.wordCount)")
        lines.append("- Model: \(document.metadata.modelProfile)")
        if !document.speakers.isEmpty {
            lines.append("")
            lines.append("## Speakers")
            for speaker in document.speakers {
                lines.append("- \(speaker.label)\(speaker.isSelf ? " (you)" : "")")
            }
        }
        lines.append("")
        lines.append("## Transcript")
        lines.append("")
        for segment in document.segments {
            let who = segment.speaker.flatMap { labels[$0] } ?? "Unknown"
            lines.append("**[\(Segment.timeLabel(segment.start))] \(who) · \(segment.source):** \(segment.final)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
