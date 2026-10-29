import Foundation
import SuperflowKernel
import SuperflowMeetingEngine

enum MeetingProjection {
    static func document(record: SessionRecord, segments: [Segment],
                                 speakers: [SpeakerRecord]) -> MeetingDocument {
        let names = Dictionary(speakers.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let meetingSpeakers = speakers.map { speaker in
            seen.insert(speaker.id)
            return MeetingSpeaker(id: speaker.id, name: speaker.label, isSelf: speaker.isSelf)
        }
        let turns = segments.map { segment -> MeetingTurn in
            let speakerID = segment.speakerID ?? (segment.source == .mic ? "self" : "remote-1")
            let isGap = segment.rawText.hasPrefix("[") && segment.rawText.hasSuffix("]")
            let text = isGap ? String(segment.rawText.dropFirst().dropLast()) : segment.bestText
            return MeetingTurn(index: segment.index, speakerID: speakerID,
                               speakerName: names[speakerID] ?? (speakerID == "self" ? "You" : speakerID),
                               startMs: segment.startMs, endMs: segment.endMs, text: text,
                               rawText: segment.rawText, source: segment.source, isGap: isGap)
        }
        var allSpeakers = meetingSpeakers
        for turn in turns where !turn.isGap && !seen.contains(turn.speakerID) {
            seen.insert(turn.speakerID)
            allSpeakers.append(MeetingSpeaker(id: turn.speakerID, name: turn.speakerName,
                                              isSelf: turn.speakerID == "self"))
        }
        return MeetingDocument(sessionID: record.id,
                               title: record.title ?? record.displayTitle,
                               startedAt: record.startedAt, endedAt: record.endedAt,
                               durationMs: record.durationMs, speakers: allSpeakers, turns: turns)
    }
}
