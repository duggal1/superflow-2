import Foundation
import SuperflowKernel

public struct MeetingSpeaker: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var isSelf: Bool
    public init(id: String, name: String, isSelf: Bool) {
        self.id = id
        self.name = name
        self.isSelf = isSelf
    }
}

public struct MeetingTurn: Sendable, Equatable, Identifiable {
    public var index: Int
    public var speakerID: String
    public var speakerName: String
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var rawText: String
    public var source: AudioSourceKind
    public var isGap: Bool
    public var id: Int { index }
    public init(index: Int, speakerID: String, speakerName: String, startMs: Int, endMs: Int,
                text: String, rawText: String, source: AudioSourceKind, isGap: Bool = false) {
        self.index = index
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.rawText = rawText
        self.source = source
        self.isGap = isGap
    }
    public var timestampLabel: String { Segment.timeLabel(startMs) }
}

public struct MeetingDocument: Sendable, Equatable {
    public var sessionID: SessionID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMs: Int
    public var speakers: [MeetingSpeaker]
    public var turns: [MeetingTurn]
    public var notices: [String]

    public init(sessionID: SessionID, title: String, startedAt: Date, endedAt: Date?,
                durationMs: Int, speakers: [MeetingSpeaker], turns: [MeetingTurn],
                notices: [String] = []) {
        self.sessionID = sessionID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.speakers = speakers
        self.turns = turns
        self.notices = notices
    }

    public var durationLabel: String {
        let s = durationMs / 1000
        if s >= 3600 { return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60) }
        if s >= 60 { return String(format: "%dm %02ds", s / 60, s % 60) }
        return "\(s)s"
    }

    public var participantLabel: String {
        speakers.map(\.name).joined(separator: ", ")
    }
}
