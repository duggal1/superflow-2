import Foundation

/// The two switches the Island reads. Settings owns them; the model only mirrors
/// them, so a change of mind never needs a relaunch.
public struct IslandPrefs: Equatable, Sendable {
    /// "Always show Island": visible at rest, a click opens history.
    public var alwaysOn: Bool
    /// "Show live text": streaming always runs, this only draws it.
    public var liveText: Bool

    public init(alwaysOn: Bool = false, liveText: Bool = false) {
        self.alwaysOn = alwaysOn
        self.liveText = liveText
    }
}

/// Streaming partials. The recognizer always produces them; the model keeps the
/// current one only when the setting is on, so turning the shelf off costs no
/// engine work and turning it on needs no restart.
public struct LiveText: Equatable, Sendable {
    public var text: String
    public var speaker: String?
    public var isFinal: Bool

    public init(text: String, speaker: String? = nil, isFinal: Bool = false) {
        self.text = text
        self.speaker = speaker
        self.isFinal = isFinal
    }

    public static let empty = LiveText(text: "")
}

/// One participant's share of a meeting. `isYou` is the local microphone, which
/// the diarizer never has to name.
public struct SpeakerShare: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var seconds: Double
    public var isYou: Bool

    public init(id: String, name: String, seconds: Double, isYou: Bool) {
        self.id = id
        self.name = name
        self.seconds = seconds
        self.isYou = isYou
    }
}

/// What the meeting panel shows, about once a second. Words come from the
/// transcript; the speaker split comes from the diarizer timeline.
public struct MeetingPulse: Equatable, Sendable {
    public var words: Int
    public var speakers: [SpeakerShare]
    public var current: String?

    public init(words: Int, speakers: [SpeakerShare], current: String?) {
        self.words = words
        self.speakers = speakers
        self.current = current
    }

    public static let empty = MeetingPulse(words: 0, speakers: [], current: nil)
}

public extension IslandTranscript {
    /// Stable enough for a `ForEach` and for "this row is copied": the start
    /// instant plus the word count, not a hash of text that cleanup may rewrite.
    var id: String { "\(date.timeIntervalSinceReferenceDate)-\(words)" }
}

/// A transcription is identified by when it started; two sessions cannot share a
/// start instant to the second, and the id survives a text edit.
extension IslandTranscript: Identifiable {}

public extension IslandFeed {
    /// Streaming partials, always produced. Empty by default so a test stub only
    /// has to implement the four things it actually needs.
    var live: AsyncStream<LiveText> { AsyncStream { $0.finish() } }
    /// Meeting word count and talk share, about 1 Hz. Empty outside a meeting.
    var pulses: AsyncStream<MeetingPulse> { AsyncStream { $0.finish() } }
    /// The last `limit` dictations, newest first.
    func history(limit: Int) -> [IslandTranscript] { [] }
    /// Words dictated today, meetings excluded. The hover shelf reads it.
    func wordsToday() -> Int { 0 }
}
