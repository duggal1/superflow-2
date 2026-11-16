import Foundation
import SuperflowKernel
import SuperflowPorts

/// Removes an abandoned date/time value when the speaker explicitly revises it
/// ("Thursday actually no Wednesday"). Deliberately limited to calendar values
/// and explicit revision cues: ordinary "no" and "actually" are never deleted,
/// so negation and casual speech stay byte-identical.
enum SelfCorrection: Sendable {
    private static let calendar = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|"
        + "january|february|march|april|may|june|july|august|september|october|november|december"
    private static let pattern = "(?i)\\b(" + calendar
        + ")\\s+(?:actually\\s+no|actually|i\\s+mean|no,)\\s+(" + calendar + ")\\b"
    private static let regex = try? NSRegularExpression(pattern: pattern)

    static func apply(_ input: String) -> String {
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
