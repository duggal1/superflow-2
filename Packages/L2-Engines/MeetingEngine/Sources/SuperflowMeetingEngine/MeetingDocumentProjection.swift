import Foundation
import SuperflowKernel

/// Single source of truth for turning persisted segments into a meeting document. The live
/// window and the final repository-backed document use the same gap/drop markers, so an echo
/// dropped during capture never reappears after a restart.
public enum MeetingDocumentProjection {
    public static let gapSpeakerID = "system"
    public static let gapSpeakerName = "System audio"

    public static func isGap(_ segment: Segment) -> Bool {
        if segment.speakerID == gapSpeakerID, segment.cleanupState == .skipped,
           (segment.cleanedText ?? "").isEmpty {
            return true
        }
        let raw = segment.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasPrefix("[") && raw.hasSuffix("]")
    }

    public static func isDropped(_ segment: Segment) -> Bool {
        guard !isGap(segment) else { return false }
        return segment.cleanupState == .skipped && (segment.cleanedText ?? "").isEmpty
    }

    public static func make(record: SessionRecord, segments: [Segment],
                            speakers: [SpeakerRecord], notices: [String] = [],
                            endedAt: Date? = nil, durationMs: Int? = nil) -> MeetingDocument {
        let names = Dictionary(speakers.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var turns: [MeetingTurn] = []
        for segment in segments where !isDropped(segment) {
            let gap = isGap(segment)
            let speakerID = gap ? gapSpeakerID
                : (segment.speakerID ?? (segment.source == .mic ? "self" : "remote-1"))
            let text = gap ? gapText(segment) : segment.bestText
            let name = gap ? gapSpeakerName : speakerName(id: speakerID, names: names)
            turns.append(MeetingTurn(index: segment.index, speakerID: speakerID, speakerName: name,
                                     startMs: segment.startMs, endMs: segment.endMs, text: text,
                                     rawText: segment.rawText, source: segment.source,
                                     isGap: gap))
        }
        turns.sort { $0.startMs == $1.startMs ? $0.index < $1.index : $0.startMs < $1.startMs }
        let meetingSpeakers = speakerList(turns: turns, records: speakers)
        let audioDuration = turns.map(\.endMs).max() ?? 0
        let end = endedAt ?? record.endedAt
        let wallMs = end.map { max(0, Int($0.timeIntervalSince(record.startedAt) * 1000)) } ?? 0
        return MeetingDocument(sessionID: record.id, title: title(for: record),
                               startedAt: record.startedAt, endedAt: end,
                               durationMs: durationMs ?? max(record.durationMs, max(audioDuration, wallMs)),
                               speakers: meetingSpeakers, turns: turns, notices: notices)
    }

    public static func make(record: SessionRecord, turns: [MeetingTurn], notices: [String],
                            endedAt: Date?, durationMs: Int) -> MeetingDocument {
        let sorted = turns.sorted {
            $0.startMs == $1.startMs ? $0.index < $1.index : $0.startMs < $1.startMs
        }
        return MeetingDocument(sessionID: record.id, title: title(for: record),
                               startedAt: record.startedAt, endedAt: endedAt,
                               durationMs: durationMs, speakers: speakerList(turns: sorted, records: []),
                               turns: sorted, notices: notices)
    }

    public static func speakerName(id: String, names: [String: String]) -> String {
        if let name = names[id] { return name }
        if id == "self" { return "You" }
        if let suffix = id.split(separator: "-").last, let number = Int(suffix) {
            return "Speaker \(number)"
        }
        return id
    }

    public static func speakerList(turns: [MeetingTurn], records: [SpeakerRecord]) -> [MeetingSpeaker] {
        let names = Dictionary(records.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var result: [MeetingSpeaker] = []
        var seen = Set<String>()
        for turn in turns where !turn.isGap && !seen.contains(turn.speakerID) {
            seen.insert(turn.speakerID)
            result.append(MeetingSpeaker(id: turn.speakerID,
                                         name: names[turn.speakerID] ?? turn.speakerName,
                                         isSelf: turn.speakerID == "self"))
        }
        return result.sorted {
            if $0.isSelf != $1.isSelf { return $0.isSelf }
            return $0.id < $1.id
        }
    }

    static func gapText(_ segment: Segment) -> String {
        let raw = segment.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("["), raw.hasSuffix("]") {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }

    static func title(for record: SessionRecord) -> String {
        if let title = record.title, !title.isEmpty { return title }
        return "Meeting · " + titleFormatter.string(from: record.startedAt)
    }

    static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension MeetingEngine {
    func liveDocument(record: SessionRecord) -> MeetingDocument {
        MeetingDocumentProjection.make(record: record, turns: residentTurns, notices: notices,
                                       endedAt: nil, durationMs: max(lastEndMs, 0))
    }

    func repositoryDocument(endedAt: Date) async -> MeetingDocument {
        guard let record else {
            return MeetingDocument(sessionID: "unknown", title: "Meeting", startedAt: endedAt,
                                   endedAt: endedAt, durationMs: lastEndMs, speakers: [], turns: [],
                                   notices: notices)
        }
        let segments = (try? await repository.segments(session: record.id)) ?? []
        let speakers = (try? await repository.speakers(session: record.id)) ?? []
        let wallMs = max(0, Int(endedAt.timeIntervalSince(record.startedAt) * 1000))
        return MeetingDocumentProjection.make(record: record, segments: segments,
                                              speakers: speakers, notices: notices,
                                              endedAt: endedAt,
                                              durationMs: max(lastEndMs, wallMs))
    }

    func cleanupStateFromRepository() async -> CleanupState {
        guard let record,
              let segments = try? await repository.segments(session: record.id) else {
            return .skipped
        }
        let states = segments.filter { !MeetingDocumentProjection.isGap($0) }
            .map(\.cleanupState)
        if states.contains(.fallback) { return .fallback }
        if states.contains(.cleaned) { return .cleaned }
        return .skipped
    }
}
