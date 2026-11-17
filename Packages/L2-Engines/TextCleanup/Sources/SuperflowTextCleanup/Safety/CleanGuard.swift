import Foundation
import SuperflowKernel
import SuperflowPorts

public enum CleanGuard {
    public enum Failure: String, Error, Sendable { case truncated, protectedLost, contentChanged, empty, quoteChanged }

    public static func verify(input: String, protected: Protected, result: CleanResult, cap: Int) -> Failure? {
        if result.hitTokenCap || result.tokensOut >= cap { return .truncated }
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !protected.ranges(in: input, detect: false).isEmpty { return .protectedLost }
            return FillerOnlyText.isFillerOnly(input) ? nil : .empty
        }
        let spans = protected.ranges(in: input, detect: false).sorted { $0.lowerBound < $1.lowerBound }
        var end = input.startIndex
        var cursor = result.text.startIndex
        for span in spans where span.lowerBound >= end {
            let literal = String(input[span])
            guard let match = result.text.range(of: literal, range: cursor..<result.text.endIndex),
                  boundary(result.text, match.lowerBound, before: true),
                  boundary(result.text, match.upperBound, before: false) else { return .protectedLost }
            cursor = match.upperBound
            end = span.upperBound
        }
        let comparable = ListPlanner.plan(input, protected: protected).map { segment in
            switch segment {
            case .prose(let text): text
            case .list(let lead, let items): ([lead] + items).joined(separator: " ")
            }
        }.joined(separator: " ")
        // Enumeration labels are formatting; numbers within items remain data.
        let data = Tokenizer.tokens(in: comparable).filter {
            $0.core.contains(where: \.isNumber) || $0.core.contains("_") || $0.core.contains("/") || $0.core.contains(".")
        }.map(\.core)
        // Paths and dotted identifiers still need an exact match; a modified
        // one ("hero.tsxbackup") must never pass as formatting.
        for literal in data where !literal.contains(where: \.isNumber) {
            guard let match = result.text.range(of: literal, options: .caseInsensitive,
                                                range: result.text.startIndex..<result.text.endIndex),
                  boundary(result.text, match.lowerBound, before: true),
                  boundary(result.text, match.upperBound, before: false) else { return .protectedLost }
        }
        // S1-mini renders quantities in written form ("200ms" -> "200 ms").
        // Compare whole digit runs so formatting passes but 500 -> 1500 fails.
        // A leading "Step 10" / "Item 3" marker is layout, not data; S1-mini
        // may drop it without changing the instruction.
        let withoutEnumeration = comparable.replacingOccurrences(
            of: #"^\s*(?:step|item|number|point)\s+[0-9]+\s*"#,
            with: "", options: .regularExpression)
        let sourceDigits = Self.digitRuns(withoutEnumeration)
        let resultDigits = Self.digitRuns(result.text)
        for run in Set(sourceDigits) {
            guard resultDigits.filter({ $0 == run }).count >= sourceDigits.filter({ $0 == run }).count else {
                return .protectedLost
            }
        }
        let sourcePaths = Set(Tokenizer.tokens(in: comparable).map(\.core)
            .filter { $0.contains("/") && $0.contains(where: \.isLetter) }.map { $0.lowercased() })
        let outputPaths = Tokenizer.tokens(in: result.text).map(\.core)
            .filter { $0.contains("/") && $0.contains(where: \.isLetter) }.map { $0.lowercased() }
        // A model may legitimately COMPLETE a spoken path: Tier 0 stops at the
        // first path token ("lib/backend/.../prospect") while the model joins the
        // spoken "dash main dash engine dot t s" suffix into the same path. An
        // output path is accepted when it equals a source path or extends one at
        // a token boundary; a different or shortened path is still rejected.
        if !sourcePaths.isEmpty {
            guard outputPaths.allSatisfy({ output in
                sourcePaths.contains { source in
                    output == source || output.hasPrefix(source + "/") || output.hasPrefix(source + "-")
                        || output.hasPrefix(source + ".")
                }
            }) else { return .contentChanged }
        } else if !outputPaths.isEmpty {
            // No literal path in the source. A model may only introduce one when
            // the speaker actually dictated separators ("lib slash backend").
            // Otherwise this is an invented separator in ordinary prose and is
            // still rejected.
            let spokenSeparators: Set<String> = ["slash", "backslash", "dot", "dash", "hyphen", "underscore"]
            let hasSpokenPath = Tokenizer.tokens(in: comparable)
                .contains { spokenSeparators.contains($0.core.lowercased()) }
            if !hasSpokenPath { return .contentChanged }
        }
        let allowsRevision = MeaningCarriers.hasRevisionCue(comparable)
        guard MeaningCarriers.accepts(comparable, result.text,
                                      allowsRevision: allowsRevision) else { return .contentChanged }
        let source = content(comparable)
        let cleaned = content(result.text)
        guard !cleaned.isEmpty else { return .contentChanged }
        // S1-mini is a normalizer: grammar, false starts and explicit corrections
        // legitimately change word order and vocabulary. Exact lexical equality
        // rejects that work. Keep the hard data checks above and reject gross loss.
        if !allowsRevision, source.count > 12, cleaned.count * 2 < source.count { return .truncated }
        // Tail loss (e.g. a chunked cleaner dropping the last word of a chunk)
        // is not caught by the coarse count ratio; check the trailing word.
        let tailCheckedInput = comparable.split(whereSeparator: \.isWhitespace).reversed()
            .drop(while: { fillers.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) })
            .reversed().joined(separator: " ")
        if TruncationDetector().detect(input: tailCheckedInput, output: result.text,
                                      hitTokenCap: result.hitTokenCap,
                                      allowsRevision: allowsRevision) == .missingTail {
            return .truncated
        }
        return nil
    }

    private static func digitRuns(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[0-9]+") else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func boundary(_ text: String, _ index: String.Index, before: Bool) -> Bool {
        if before, index == text.startIndex { return true }
        if !before, index == text.endIndex { return true }
        let character = text[before ? text.index(before: index) : index]
        return !character.isLetter && !character.isNumber && !"_/@$€£₹¥".contains(character)
    }

    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "hm", "mm", "mmm"]
    private static let expansions: [String: [String]] = [
        "gonna": ["going", "to"], "wanna": ["want", "to"], "gotta": ["got", "to"],
        "kinda": ["kind", "of"], "sorta": ["sort", "of"], "dunno": ["do", "not", "know"],
        "lemme": ["let", "me"], "gimme": ["give", "me"], "im": ["i", "am"],
        "ive": ["i", "have"], "id": ["i", "would"], "youre": ["you", "are"],
        "theyre": ["they", "are"], "cant": ["can", "not"], "cannot": ["can", "not"],
        "wont": ["will", "not"], "dont": ["do", "not"], "doesnt": ["does", "not"],
        "didnt": ["did", "not"], "isnt": ["is", "not"], "arent": ["are", "not"],
        "wasnt": ["was", "not"], "havent": ["have", "not"], "couldnt": ["could", "not"],
        "wouldnt": ["would", "not"], "shouldnt": ["should", "not"], "thats": ["that", "is"],
        "its": ["it", "is"], "whats": ["what", "is"], "lets": ["let", "us"],
        "theres": ["there", "is"], "heres": ["here", "is"],
    ]
    private static func content(_ text: String) -> [String] {
        let unmarked = text.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: #"^\s*(?:[-*•]|[0-9]+[.)])\s+"#, with: "", options: .regularExpression)
        }.joined(separator: "\n")
        let words = unmarked.split(whereSeparator: \.isWhitespace).map {
            String($0.lowercased().filter { $0.isLetter || $0.isNumber || "$€£₹¥%@_/-".contains($0) })
        }.filter { !$0.isEmpty && !fillers.contains($0) }
        var result: [String] = []
        var index = 0
        while index < words.count {
            if index + 2 < words.count, Array(words[index...index + 2]) == ["you", "know", "like"] {
                index += 3; continue
            }
            result.append(contentsOf: expansions[words[index]] ?? [words[index]])
            index += 1
        }
        return result
    }
}
