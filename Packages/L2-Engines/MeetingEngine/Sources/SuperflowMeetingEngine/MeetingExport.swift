import Foundation
import SuperflowKernel

public enum MeetingExport {
    public struct Options: Sendable {
        public var timeZone: TimeZone
        public var locale: Locale

        public init(timeZone: TimeZone = .current, locale: Locale = .current) {
            self.timeZone = timeZone
            self.locale = locale
        }

        /// Stable output for golden tests and for exports that must not vary by machine.
        public static let deterministic = Options(timeZone: TimeZone(secondsFromGMT: 0)!,
                                                 locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func markdown(_ doc: MeetingDocument,
                                options: Options = Options()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = options.timeZone
        formatter.locale = options.locale
        var lines: [String] = []
        lines.append("# \(doc.title)")
        lines.append("")
        lines.append("**Date:** \(formatter.string(from: doc.startedAt))")
        lines.append("**Duration:** \(doc.durationLabel)")
        lines.append("**Participants:** \(doc.participantLabel.isEmpty ? "You" : doc.participantLabel)")
        lines.append("")
        for turn in sortedTurns(doc) {
            if turn.isGap {
                lines.append("_[\(turn.text)]_")
                lines.append("")
                continue
            }
            lines.append("**\(turn.speakerName)** · \(turn.timestampLabel)")
            lines.append(turn.text)
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public static func jsonData(_ doc: MeetingDocument,
                                options: Options = Options()) throws -> Data {
        let payload = JSONDocument(doc, options: options)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func sortedTurns(_ doc: MeetingDocument) -> [MeetingTurn] {
        doc.turns.sorted { $0.startMs == $1.startMs ? $0.index < $1.index : $0.startMs < $1.startMs }
    }

    private struct JSONDocument: Encodable {
        let schemaVersion: Int
        let meeting: JSONMeeting
        let speakers: [JSONSpeaker]
        let segments: [JSONSegment]

        init(_ doc: MeetingDocument, options: Options) {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = options.timeZone
            formatter.formatOptions = [.withInternetDateTime]
            schemaVersion = 1
            meeting = JSONMeeting(id: doc.sessionID.value, title: doc.title,
                                  startedAt: formatter.string(from: doc.startedAt),
                                  endedAt: doc.endedAt.map(formatter.string(from:)),
                                  durationMs: doc.durationMs)
            speakers = doc.speakers.map {
                JSONSpeaker(id: $0.id, name: $0.name, isSelf: $0.isSelf)
            }
            segments = MeetingExport.sortedTurns(doc).map {
                JSONSegment(startMs: $0.startMs, endMs: $0.endMs, speaker: $0.speakerName,
                            text: $0.text, rawText: $0.rawText, isGap: $0.isGap)
            }
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion, meeting, speakers, segments
        }
    }

    private struct JSONMeeting: Encodable {
        let id: String
        let title: String
        let startedAt: String
        let endedAt: String?
        let durationMs: Int
        enum CodingKeys: String, CodingKey {
            case id, title, startedAt = "started_at", endedAt = "ended_at", durationMs = "duration_ms"
        }
    }

    private struct JSONSpeaker: Encodable {
        let id: String
        let name: String
        let isSelf: Bool
        enum CodingKeys: String, CodingKey {
            case id, name, isSelf = "is_self"
        }
    }

    private struct JSONSegment: Encodable {
        let startMs: Int
        let endMs: Int
        let speaker: String
        let text: String
        let rawText: String
        let isGap: Bool
        enum CodingKeys: String, CodingKey {
            case startMs = "start_ms", endMs = "end_ms", speaker, text,
                 rawText = "raw_text", isGap = "is_gap"
        }
    }
}
