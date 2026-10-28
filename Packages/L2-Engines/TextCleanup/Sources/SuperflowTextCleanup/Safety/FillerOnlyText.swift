import Foundation

/// S1-mini's contract says filler-only or noise-only input normalizes to an
/// empty string. This gate separates that successful empty result from a model
/// failure on content-bearing input, which must still fall back to Tier 0.
enum FillerOnlyText {
    private static let fillers: Set<String> = [
        "ah", "eh", "er", "erm", "hmm", "huh", "mhm", "mm", "mmm",
        "oh", "uh", "uhm", "um",
    ]

    private static let elongatedBases = ["um", "uh", "hmm", "erm", "er", "ah", "mm", "oh"]

    static func isFillerOnly(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return true }
        return words.allSatisfy { isFillerOrNoise(String($0)) }
    }

    private static func isFillerOrNoise(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if isAnnotation(trimmed) { return true }

        let core = trimmed.lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
        guard !core.isEmpty else { return true }
        if fillers.contains(core) { return true }
        return isElongatedFiller(core)
    }

    /// Non-speech markers from ASR, such as `[noise]`, `(inaudible)` or `♪`.
    private static func isAnnotation(_ word: String) -> Bool {
        guard word.count >= 2, let first = word.first, let last = word.last else { return false }
        switch (first, last) {
        case ("[", "]"), ("(", ")"), ("<", ">"), ("*", "*"), ("♪", "♪"):
            return true
        default:
            return false
        }
    }

    private static func isElongatedFiller(_ word: String) -> Bool {
        for base in elongatedBases where word.count > base.count && word.hasPrefix(base) {
            guard let last = base.last else { continue }
            if word.dropFirst(base.count).allSatisfy({ $0 == last }) { return true }
        }
        return false
    }
}
