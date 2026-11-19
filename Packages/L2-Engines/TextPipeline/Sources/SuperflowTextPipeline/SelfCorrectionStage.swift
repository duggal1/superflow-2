import Foundation
import SuperflowKernel
import SuperflowPorts

/// Resolves an explicit self-correction to the single value the speaker landed
/// on. "no wait", "no,", "sorry", "actually", "i mean" and "make that" are
/// revision cues; the abandoned value before the cue is discarded and only the
/// final value survives. Calendars, spoken clock times and number phrases are
/// covered because those are the values dictation most often revises.
///
/// The resolver is deliberately narrow: a cue must sit between two values of
/// the same kind. Ordinary "no" (negation) and "actually" (emphasis) and
/// contrastive phrases ("not X but Y", "I actually no longer need X") never
/// match, so no factual content is quietly deleted. Protected spans are never
/// rewritten.
enum SelfCorrection: Sendable {
    private static let gap = "[ \\t]+"
    private static let day = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|"
        + "january|february|march|april|may|june|july|august|september|october|november|december"
    private static let digitWord = "(?:zero|oh|one|two|three|four|five|six|seven|eight|nine|ten|"
        + "eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|"
        + "thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|\\d+)"
    private static let numberPhrase = digitWord + "(?:" + gap + digitWord + "){0,3}"
    private static let hours = "(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|noon|midnight|\\d{1,2})"
    private static let minutes = "(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|\\d{1,2})"
    private static let meridiem = "(?:\\s*(?:p|a)\\s*\\.?\\s*m\\.?|pm|am)"
    private static let clock = hours
        + "(?:(?:\\s+(?:oh|o|zero))?" + gap + "(?:" + minutes + "))?"
        + "(?:" + meridiem + ")?"

    /// A cue may be followed by a bridging word ("no wait make that Friday",
    /// "actually no I mean Friday") before the final value appears.
    private static let cue = "(?:no\\s+wait|actually\\s+no(?:\\s+wait)?|no\\s+sorry|sorry|actually|i\\s+mean|no,|make\\s+that)"
    private static let bridge = "(?:" + gap + "(?:make\\s+that|i\\s+mean|wait|sorry))?"
    /// A comma may sit between the abandoned value and its revision cue.
    private static let beforeCue = "(?:,[ \\t]*)?" + gap
    /// A date may carry an ordinal ("March third" / "March 3rd"); keep it with
    /// the day so a revised date keeps the final day *and* the final ordinal.
    private static let ordinal = "(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|"
        + "eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|"
        + "twentieth|\\d{1,2}(?:st|nd|rd|th)?)"
    private static let datedDay = "((?:" + day + ")(?:" + gap + ordinal + ")?)"

    private static let dayPattern = "(?i)\\b" + datedDay + beforeCue + cue + bridge
        + gap + datedDay + "\\b"
    private static let numberPattern = "(?i)\\b(" + numberPhrase + ")" + beforeCue + cue + bridge
        + gap + "(" + numberPhrase + ")\\b"
    /// A repeated code/path literal with an explicit revision cue resolves to
    /// the second value ("hero.tsx no wait hero.tsx" -> "hero.tsx").
    private static let codeLiterals = "[A-Za-z0-9_/\\\\.:-]+\\.[A-Za-z]{1,8}"
    private static let codeRepeatPattern = "(?i)\\b(" + codeLiterals + ")" + beforeCue + cue + bridge
        + gap + "\\1\\b"
    private static let timePattern = "(?i)\\b(at|on|by|around)" + gap + "(" + clock + ")"
        + gap + "on" + gap + "(" + day + ")" + beforeCue + cue + bridge
        + gap + "(" + day + ")" + gap + "at" + gap + "(" + clock + ")\\b"

    static func apply(_ input: String, protected: Protected = Protected()) -> String {
        guard !input.isEmpty else { return input }
        var text = input
        // Chained revisions ("Thursday actually no Wednesday sorry Friday") are
        // resolved inside-out; the bound keeps the pass linear and finite.
        for _ in 0..<4 {
            let times = replace(timePattern, in: text, protected: protected) { match, source in
                guard let preposition = source.group(1, in: match),
                      let finalClock = source.group(5, in: match),
                      let finalDay = source.group(4, in: match) else { return nil }
                return preposition + " " + finalClock + " on " + finalDay
            }
            let code = replace(codeRepeatPattern, in: times, protected: protected) { match, source in
                source.group(1, in: match).map { String($0) }
            }
            let days = replace(dayPattern, in: code, protected: protected) { match, source in
                source.group(2, in: match).map { String($0) }
            }
            let next = replace(numberPattern, in: days, protected: protected) { match, source in
                source.group(2, in: match).map { String($0) }
            }
            if next == text { break }
            text = next
        }
        return text
    }

    /// Replaces every non-overlapping match with the value the speaker landed
    /// on. Matches crossing a newline or touching a protected span are skipped
    /// so a list or email layout can never be merged into one sentence.
    private static func replace(_ pattern: String, in input: String,
                                protected: Protected,
                                replacement: (NSTextCheckingResult, String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let protectedRanges = protected.ranges(in: input, detect: false)
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        var output = ""
        var cursor = 0
        for match in matches {
            guard let range = Range(match.range, in: input),
                  !input[range].contains("\n"),
                  !protected.overlaps(range, in: input),
                  match.range.location >= cursor,
                  let value = replacement(match, input) else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += value
            cursor = NSMaxRange(match.range)
        }
        guard cursor > 0 else { return input }
        output += ns.substring(from: cursor)
        return output
    }
}

private extension String {
    func group(_ index: Int, in match: NSTextCheckingResult) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let swift = Range(range, in: self) else { return nil }
        return String(self[swift])
    }
}

struct SelfCorrectionStage: SuperflowPorts.TextStage {
    let id = "selfCorrection"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        output.text = SelfCorrection.apply(draft.text, protected: draft.protected)
        return output
    }
}
