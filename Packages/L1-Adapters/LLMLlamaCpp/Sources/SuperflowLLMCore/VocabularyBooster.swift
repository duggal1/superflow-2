import Foundation

/// Loudness of a vocabulary boost. Mirrors HEX `vocabulary_boost`
/// (Off / Light 2.0 / Normal 2.5 / Strong 4.0 nats per piece). We cannot rescore
/// transducer logits from Swift, so the strength maps to a string-similarity
/// gate instead; see the report for the honest limitation.
public enum VocabularyBoostLevel: String, Sendable, CaseIterable {
    case off, light, normal, strong

    /// Minimum normalized similarity required before a candidate span is
    /// replaced by the canonical term.
    var similarityGate: Float {
        switch self {
        case .off: return 1.01
        case .light: return 0.78
        case .normal: return 0.66
        case .strong: return 0.55
        }
    }
}

public struct VocabularyTerm: Sendable, Equatable {
    public let canonical: String
    /// Sounds-like spellings the owner supplied, e.g. "a bat war" for Abattoir.
    public let aliases: [String]

    public init(_ canonical: String, aliases: [String] = []) {
        self.canonical = canonical
        self.aliases = aliases
    }
}

/// Post-recognition term booster, ported from HEX's `vocabulary.cpp` ideas:
/// find 1-4 word spans that look like a listed term, skip case-only and
/// inflection differences and paths, then replace only when the audio-shaped
/// candidate is close enough. It never inserts a term where nothing was said,
/// which is the failure mode that made HEX reject token-time boosting.
public struct VocabularyBooster: Sendable {
    public let terms: [VocabularyTerm]
    public let level: VocabularyBoostLevel

    public init(terms: [VocabularyTerm], level: VocabularyBoostLevel = .normal) {
        self.terms = terms
        self.level = level
    }

    public func apply(_ text: String) -> String {
        guard level != .off, !terms.isEmpty else { return text }
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return text }

        var index = 0
        while index < words.count {
            if Self.isPath(words[index]) { index += 1; continue }
            var best: (length: Int, canonical: String, score: Float)?
            for length in stride(from: min(4, words.count - index), through: 1, by: -1) {
                let span = words[index..<(index + length)].joined(separator: " ")
                for term in terms {
                    let forms = [term.canonical] + term.aliases
                    if Self.isTrivialVariant(span, forms: forms) { continue }
                    for form in forms {
                        let score = Self.similarity(span, form)
                        guard score >= level.similarityGate else { continue }
                        if let current = best, current.score >= score { continue }
                        best = (length, term.canonical, score)
                    }
                }
                if best != nil { break } // Prefer the longest matching span.
            }
            if let match = best {
                words[index] = match.canonical
                if match.length > 1 { words.removeSubrange((index + 1)..<(index + match.length)) }
            }
            index += 1
        }
        return words.joined(separator: " ")
    }

    /// Longest-common-subsequence similarity, 0...1. LCS tolerates word-order
    /// insertions ("a bat war" vs "abattoir") better than raw edit distance
    /// while still rejecting unrelated words such as "about".
    static func similarity(_ lhs: String, _ rhs: String) -> Float {
        let a = normalized(lhs)
        let b = normalized(rhs)
        if a == b { return 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = [Int](repeating: 0, count: b.count + 1)
        for left in a {
            for (offset, right) in b.enumerated() {
                current[offset + 1] = left == right
                    ? previous[offset] + 1
                    : max(current[offset], previous[offset + 1])
            }
            swap(&previous, &current)
            for offset in current.indices { current[offset] = 0 }
        }
        return Float(previous[b.count]) / Float(max(a.count, b.count))
    }

    private static func normalized(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value.lowercased() {
            if character.isLetter || character.isNumber { result.append(character) }
        }
        return result
    }

    private static func isPath(_ token: String) -> Bool {
        token.hasPrefix("~") || token.contains(where: { "/@:\\_".contains($0) })
    }

    private static func isTrivialVariant(_ span: String, forms: [String]) -> Bool {
        // An exact canonical match is already correct; an exact *alias* match
        // is the sounds-like spelling we are supposed to replace.
        if forms.first == span { return true }
        let a = normalized(span)
        let allowed = Set(forms.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .map { $0.lowercased() })
        for form in forms {
            let b = normalized(form)
            for suffix in ["s", "ed", "ing"] where b.count > 3 && a == b + suffix { return true }
        }
        // Never swallow an ordinary function word just to make a span look like
        // a term ("the open code" must not become just "OpenCode").
        let spanWords = span.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        if spanWords.count > 1,
           spanWords.contains(where: { Self.functionWords.contains($0) && !allowed.contains($0) }) {
            return true
        }
        return false
    }

    private static let functionWords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "with",
        "is", "are", "was", "we", "you", "please", "this", "that", "should", "will",
    ]
}
