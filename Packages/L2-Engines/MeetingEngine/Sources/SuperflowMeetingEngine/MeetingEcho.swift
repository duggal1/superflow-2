import Foundation
import SuperflowKernel

/// Conservative evidence gate for removing a microphone turn that merely repeats system audio.
///
/// Ported from hex's meeting echo rules with the v1-compatible subset only: one shared timeline,
/// a bounded delay window, and order-aware word similarity. Acoustic bleed classification needs
/// per-turn raw energy state and is deliberately not part of this gate — when in doubt, a
/// microphone turn is kept. Deleting legitimate simultaneous speech is the worse error.
public enum MeetingEcho {
    /// Remote speech reaches the microphone tens of milliseconds later; hex judges matches
    /// within about 1.5 seconds. Beyond that, equal words are a coincidence, not echo.
    public static let maxLagMs = 1_500
    /// Fraction of the shorter turn's time span that must be shared, on the shared clock.
    public static let minimumOverlap = 0.5
    /// Words must match in order at this rate before a microphone turn may be removed. Deliberately
    /// stricter than hex's 60% word match: without its acoustic bleed signal, a near match can be
    /// two people talking over each other, so only near-identical wording counts as evidence.
    public static let minimumSimilarity = 0.9
    /// A one-word coincidence (for example two people saying "yes") is not evidence.
    public static let minimumWords = 2

    /// True only when `mic` repeats `system` on the shared clock: starts are close, time spans
    /// overlap substantially, both sides have enough words, and the words match in order.
    public static func isEcho(mic: MeetingTurn, system: MeetingTurn) -> Bool {
        guard !mic.isGap, !system.isGap, mic.source == .mic, system.source == .system else {
            return false
        }
        guard abs(mic.startMs - system.startMs) <= maxLagMs else { return false }
        guard overlapRatio(mic, system) >= minimumOverlap else { return false }
        let micWords = tokens(mic.rawText)
        let systemWords = tokens(system.rawText)
        guard micWords.count >= minimumWords, systemWords.count >= minimumWords else { return false }
        return similarity(micWords, systemWords) >= minimumSimilarity
    }

    /// Overlap as a fraction of the shorter turn, so a short echo inside a long remote turn still
    /// counts as aligned without letting a tiny sliver justify a deletion.
    public static func overlapRatio(_ a: MeetingTurn, _ b: MeetingTurn) -> Double {
        let overlap = max(0, min(a.endMs, b.endMs) - max(a.startMs, b.startMs))
        let shortest = max(1, min(a.endMs - a.startMs, b.endMs - b.startMs))
        return Double(overlap) / Double(shortest)
    }

    /// Longest-common-subsequence similarity over normalized word sequences, normalized by the
    /// longer side. Unlike a word-set ratio this respects order and repeated words, so two people
    /// talking at once about different things cannot look like the same sentence.
    public static func similarity(_ first: String, _ second: String) -> Double {
        similarity(tokens(first), tokens(second))
    }

    private static func similarity(_ first: [String], _ second: [String]) -> Double {
        let longest = max(first.count, second.count)
        guard longest > 0 else { return 0 }
        if first == second { return 1 }
        var previous = [Int](repeating: 0, count: second.count + 1)
        var current = [Int](repeating: 0, count: second.count + 1)
        for a in first {
            for (index, b) in second.enumerated() {
                current[index + 1] = a == b
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            swap(&previous, &current)
            current = [Int](repeating: 0, count: second.count + 1)
        }
        return Double(previous[second.count]) / Double(longest)
    }

    private static func tokens(_ text: String) -> [String] {
        Tokenizer.words(in: text.lowercased()).map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
    }
}
