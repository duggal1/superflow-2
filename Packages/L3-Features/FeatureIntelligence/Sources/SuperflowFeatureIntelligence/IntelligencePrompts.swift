import Foundation
import SuperflowMeetingIntelligence

public enum IntelligencePrompts {
    /// THE one shared block for messy speech-to-text. Embedded exactly once by
    /// every task below, so typed asks, push-to-talk and meeting auto-detection
    /// all interpret garbled ASR the same way.
    public static let messyTranscriptBlock = """
    INPUT IS MESSY SPEECH-TO-TEXT. Silently repair it before acting:
    - strip fillers, false starts, repeated words, cross-talk and speaker labels
    - recover misheard words from context (e.g. "cooper netties" is Kubernetes)
    - a trailing "…" means the speaker is still talking; do not answer a half sentence
    - infer the speaker's intent from what they are trying to get done, not literal wording
    - use SCREEN text when present; never claim screen content that is not there
    Answer the repaired intent directly, in the speaker's language. Never quote or
    comment on recognition errors. Silence or an empty utterance is not a question.
    """

    public static func askTask(_ question: String) -> String {
        messyTranscriptBlock + "\n\nTASK: Answer ME's question directly.\nQUESTION:\n\(question)"
    }

    public static func meetingDetectionTask() -> String {
        messyTranscriptBlock + """
        \n\nTASK: Decide whether the latest utterance is a question ME needs answered now.
        Reply "yes" then the repaired question on one line, or "no" and nothing else.
        Ignore small talk, fillers and statements. A question about the on-screen work counts.
        """
    }

    public static func suggestionsTask() -> String {
        messyTranscriptBlock + """
        \n\nTASK: From the transcript, write 4 to 5 short follow-up questions ME could ask next.
        One per line, numbered, no other text. Each must be answerable from the conversation
        or the screen and must stand alone without this instruction.
        """
    }

    /// Existing prompt library, wrapped unchanged.
    public static func system(mode: MeetingMode, custom: String) -> String {
        Prompts.system(mode: mode, custom: custom)
    }

    public static func user(background: String, transcript: String, screen: String?, task: String) -> String {
        Prompts.user(background: background, transcript: transcript, screen: screen, task: task)
    }
}

/// Lightweight, dependency-free question detection. The sensitivity constant is
/// exposed so the meeting flow can tune it without touching this helper.
public enum IntelligenceQuestionDetector {
    /// 0...1. Higher requires more question signal per word.
    public static let sensitivity: Double = 0.55

    private static let openers: Set<String> = [
        "what", "why", "how", "when", "where", "who", "which", "can", "could",
        "would", "should", "does", "did", "is", "are", "will", "do", "any",
    ]

    public static func looksLikeQuestion(
        _ text: String, sensitivity: Double = IntelligenceQuestionDetector.sensitivity
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let words = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        // A statement of fewer than two words is never a question on its own.
        guard words.count >= 2 else { return false }

        var signal = 0.0
        if trimmed.contains("?") { signal += 1.6 }
        if let first = words.first, openers.contains(first) { signal += 1.2 }
        else if words.prefix(4).contains(where: { openers.contains($0) }) { signal += 0.9 }
        if words.count <= 12 { signal += 0.3 }
        let threshold = min(1, max(0, sensitivity)) * 1.9
        return signal >= threshold
    }
}
