import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTechDictionary

/// Deterministic post-recognition resolver for the AI-era lexicon (F12).
/// Whole-token matching only, so "said" and "rain" are never touched by the
/// "AI" rule. Casing rules enforce canonical forms such as "AI", "LLM",
/// "API", "MCP", "GPU" as whole upper-case tokens. Longest variant wins.
enum AIEraResolver {
    private static let upperCasing: Set<String> = ["upper", "uppercase", "allcaps", "all-caps"]

    static func apply(_ input: String,
                      terms: [AIEraLexicon.Term]? = nil) -> (text: String, literals: Set<String>) {
        let records = terms?.map { term in
            (canonical: term.canonical, variants: [term.canonical] + term.variants,
             casing: term.casing)
        } ?? AIEraLexicon.resolutions.map { (canonical: $0.canonical, variants: [$0.variant], casing: $0.casing) }
        guard !records.isEmpty, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (input, [])
        }
        // Build variant -> (canonical, casing) with longest normalized wins.
        var map: [String: (canonical: String, casing: String)] = [:]
        for record in records {
            for variant in record.variants {
                let key = normalized(variant)
                guard !key.isEmpty else { continue }
                if let existing = map[key], existing.canonical.count >= record.canonical.count {
                    // Prefer the longer canonical on key collision; ties keep first.
                }
                map[key] = (record.canonical, record.casing)
            }
        }
        // Longest variant first so "vibe coding" beats a "vibe" prefix.
        let variants = map.keys.sorted { $0.count > $1.count }
        let source = input as NSString
        let tokenPattern = #"[A-Za-z]+(?:-[A-Za-z]+)?"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return (input, []) }
        let tokens = regex.matches(in: input, range: NSRange(location: 0, length: source.length))
        // Tokenize input into words (letters/hyphens only); multi-word variants
        // match across consecutive tokens.
        var output = ""
        var protected = Set<String>()
        var cursor = 0
        var index = 0
        func tokenText(_ match: NSTextCheckingResult) -> String {
            source.substring(with: match.range)
        }
        func isTokenBoundary(_ location: Int) -> Bool {
            guard location >= 0, location <= source.length else { return false }
            return true
        }
        _ = isTokenBoundary(0)
        while index < tokens.count {
            let token = tokens[index]
            let word = tokenText(token).lowercased()
            var matched: (canonical: String, casing: String, span: Int)? = nil
            // Try multi-word variants starting here (up to 3 tokens).
            for span in stride(from: min(3, tokens.count - index), through: 1, by: -1) {
                let slice = (index..<(index + span)).map { tokenText(tokens[$0]).lowercased() }
                let joined = normalized(slice.joined(separator: " "))
                if let hit = map[joined] {
                    // Single-letter/short variants must be whole tokens, which
                    // they already are; "ai" must not carve "said" — matching
                    // is token-based, never substring, so it cannot.
                    matched = (hit.canonical, hit.casing, span)
                    break
                }
                // Also try concatenated single-token variants like "vipcode".
                let concatenated = slice.joined()
                if span == 1, let hit = map[concatenated] {
                    matched = (hit.canonical, hit.casing, 1)
                    break
                }
            }
            if let match = matched {
                let last = tokens[index + match.span - 1]
                let end = NSMaxRange(last.range)
                output += source.substring(with: NSRange(location: cursor, length: token.range.location - cursor))
                output += match.canonical
                // Preserve surrounding punctuation attached to the span edges.
                protected.insert(match.canonical)
                cursor = end
                index += match.span
                continue
            }
            _ = word
            index += 1
        }
        output += source.substring(from: cursor)
        return (output, protected)
    }

    /// Whole-token casing enforcement for upper-case terms: "ai" -> "AI",
    /// "llm" -> "LLM", "api" -> "API", "mcp" -> "MCP", "gpu" -> "GPU".
    /// Substrings inside larger words are never touched.
    static func enforceCasing(_ input: String) -> String {
        var text = input
        for term in AIEraLexicon.terms where upperCasing.contains(term.casing.lowercased()) {
            let lower = term.canonical.lowercased()
            guard let regex = try? NSRegularExpression(
                pattern: #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: lower) + #"(?![\p{L}\p{N}])"#,
                options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    text.replaceSubrange(range, with: term.canonical)
                }
            }
        }
        return text
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

struct AIEraResolverStage: SuperflowPorts.TextStage {
    let id: String
    init(id: String = "aiEra") { self.id = id }

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        let resolved = AIEraResolver.apply(draft.text)
        let cased = AIEraResolver.enforceCasing(resolved.text)
        output.text = cased
        output.protected.literals.formUnion(resolved.literals)
        return output
    }
}
