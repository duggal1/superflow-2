import Foundation

/// Deterministic list detection for the cleanup control line.
///
/// The model is only ever asked for `list` structure on strong, explicit cues.
/// Everything else stays `prose`, because asking a small model to invent bullets
/// from ordinary speech is exactly the kind of change this pipeline forbids.
enum CleanupStructureDetector {
    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "finally": 6, "lastly": 6,
    ]

    private static let introCues = [
        "the following", "here are", "here's", "these are", "as follows",
        "the steps", "the checklist", "the list",
    ]

    /// Keeps an explicit user setting intact and only upgrades `prose`.
    static func structure(for text: String, configured: String) -> String {
        guard configured == "prose" else { return configured }
        return isList(text) ? "list" : configured
    }

    static func isList(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if hasBulletLines(text) { return true }
        let lower = text.lowercased()
        let clauses = clauseStarts(lower)
        let ordinalCount = orderedOrdinals(clauses)
        let hasIntro = introCues.contains { lower.contains($0) }
        if hasIntro, text.contains(":") || ordinalCount >= 2 { return true }
        return ordinalCount >= 3
    }

    private static func hasBulletLines(_ text: String) -> Bool {
        var count = 0
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let first = line.first else { continue }
            if "-*•".contains(first) { count += 1; continue }
            var digits = 0
            for character in line {
                if character.isNumber { digits += 1; continue }
                if digits > 0, character == "." || character == ")" { count += 1 }
                break
            }
        }
        return count >= 2
    }

    /// First word of each clause, split on sentence punctuation and newlines.
    private static func clauseStarts(_ text: String) -> [String] {
        text.split(whereSeparator: { ".;:!?\n".contains($0) }).compactMap { clause in
            clause.split(whereSeparator: { $0.isWhitespace }).first.map { word in
                word.trimmingCharacters(in: CharacterSet(charactersIn: "-*•(,)[]"))
            }
        }
    }

    /// Longest strictly increasing run of ordinal cues. "first ... second ...
    /// finally" is 3; "second ... first" is 1 so it cannot trigger a list.
    private static func orderedOrdinals(_ clauses: [String]) -> Int {
        var best = 0
        var current = 0
        var previous = 0
        for clause in clauses {
            guard let rank = ordinals[clause] else { continue }
            if rank > previous {
                current += 1
                previous = rank
                best = max(best, current)
            } else {
                current = 1
                previous = rank
            }
        }
        return best
    }
}
