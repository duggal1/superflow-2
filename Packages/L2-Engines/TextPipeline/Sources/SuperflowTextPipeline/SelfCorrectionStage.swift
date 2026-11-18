import Foundation
import SuperflowKernel
import SuperflowPorts

/// Removes an abandoned date/time value when the speaker explicitly revises it
/// ("Thursday actually no Wednesday"). Deliberately limited to calendar values
/// and explicit revision cues: ordinary "no" and "actually" are never deleted,
/// so negation and casual speech stay byte-identical. When the revision also
/// carries spoken times ("four p m on Thursday actually no Friday at five
/// thirty"), only the final time and day survive.
enum SelfCorrection: Sendable {
    private static let calendar = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|"
        + "january|february|march|april|may|june|july|august|september|october|november|december"
    private static let pattern = "(?i)\\b(" + calendar
        + ")\\s+(?:actually\\s+no|actually|i\\s+mean|no,)\\s+(" + calendar + ")\\b"
    private static let regex = try? NSRegularExpression(pattern: pattern)

    // Spoken clock shapes: "four p m", "five thirty", "nine twenty p m".
    // Non-capturing only, so the outer revision groups keep their indices.
    private static let hours = "(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|noon|midnight|\\d{1,2})"
    private static let minutes = "(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|\\d{1,2})"
    private static let meridiem = "(?:\\s*(?:p|a)\\s*\\.?\\s*m\\.?|pm|am)"
    private static let clock = hours
        + "(?:(?:\\s+(?:oh|o|zero))?\\s+(?:" + minutes + "))?"
        + "(?:" + meridiem + ")?"
    private static let revisionCue = "(?:actually\\s+no|no\\s+wait|sorry|actually|i\\s+mean|no,)"
    private static let timePattern = "(?i)\\b(at|on|by|around)\\s+(" + clock + ")\\s+on\\s+("
        + calendar + ")\\s+" + revisionCue + "\\s+(" + calendar + ")\\s+at\\s+(" + clock + ")\\b"
    private static let timeRegex = try? NSRegularExpression(pattern: timePattern)

    static func apply(_ input: String) -> String {
        resolveDays(in: resolveTimes(in: input))
    }

    /// Rewrites "<prep> <old time> on <old day> <cue> <new day> at <new time>"
    /// to "<prep> <new time> on <new day>", so an abandoned time cannot survive
    /// into number formatting alongside the corrected one.
    private static func resolveTimes(in input: String) -> String {
        guard let timeRegex else { return input }
        let ns = input as NSString
        let matches = timeRegex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }
        var output = ""
        var cursor = 0
        for match in matches {
            guard match.numberOfRanges == 6,
                  match.range.location >= cursor,
                  let preposition = Range(match.range(at: 1), in: input),
                  let finalClock = Range(match.range(at: 5), in: input),
                  let finalDay = Range(match.range(at: 4), in: input) else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += String(input[preposition]) + " " + String(input[finalClock]) + " on " + String(input[finalDay])
            cursor = NSMaxRange(match.range)
        }
        guard cursor > 0 else { return input }
        output += ns.substring(from: cursor)
        return output
    }

    private static func resolveDays(in input: String) -> String {
        guard let regex else { return input }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }
        var output = ""
        var cursor = 0
        for match in matches {
            guard match.numberOfRanges == 3,
                  let abandoned = Range(match.range(at: 1), in: input),
                  let chosen = Range(match.range(at: 2), in: input),
                  String(input[abandoned]).caseInsensitiveCompare(String(input[chosen])) != .orderedSame else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += String(input[chosen])
            cursor = NSMaxRange(match.range)
        }
        guard cursor > 0 else { return input }
        output += ns.substring(from: cursor)
        return output
    }
}

struct SelfCorrectionStage: SuperflowPorts.TextStage {
    let id = "selfCorrection"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        output.text = SelfCorrection.apply(draft.text)
        return output
    }
}
