import Foundation

/// Explicit, durable markers for a source that stopped producing usable speech.
///
/// Markers are stored as bracketed raw text in the segment stream, so they survive the live
/// window, a repository rebuild after a restart, and both export formats. A lost stream never
/// becomes a silent hole in the transcript and never masquerades as a speaker turn.
public enum MeetingStreamLoss {
    public static let systemUnavailable = "System audio unavailable"
    public static let systemLost = "System audio lost"
    public static let micLost = "Microphone input lost"
    public static let systemTranscriptLost = "System audio transcript unavailable"
    public static let micTranscriptLost = "Microphone transcript unavailable"
    public static let systemJournalLost = "System audio recording incomplete"
    public static let micJournalLost = "Microphone recording incomplete"

    public static func marker(_ message: String) -> String { "[\(message)]" }
}
