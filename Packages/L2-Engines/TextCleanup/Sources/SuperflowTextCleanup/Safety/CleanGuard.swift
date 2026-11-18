import Foundation
import SuperflowKernel
import SuperflowPorts

public enum CleanGuard {
    public enum Failure: String, Error, Sendable { case truncated, protectedLost, contentChanged, empty, quoteChanged }

    /// Input-side facts for one chunk, computed once and reused by every guard
    /// check for that chunk (initial attempt plus each retry leaf). The old
    /// path re-ran the protected-literal regex scan, ListPlanner, tokenizer and
    /// digit/multiset construction on the source for every stage and retry —
    /// O(n) work repeated on the hot cleanup path. Only result-side work stays
    /// in `verify`, so a chunk's source is scanned once.
    struct ProtectedSpan: Sendable {
        let text: String
        /// Nested inside an earlier span in the source; the original guard
        /// skipped these so an overlapping literal is not matched twice.
        let skip: Bool
    }

    public struct Basis: Sendable {
        let protectedLiterals: [ProtectedSpan] // in source order
        let hasProtectedLiteral: Bool
        let fillerOnly: Bool
        let comparable: String
        let isList: Bool
        let pathLiterals: [String]
        let allowsRevision: Bool
        let sourceDigitCounts: [String: Int]
        let sourceContentWords: [String]
        let sourceSpeaksNumbers: Bool
        let sourcePaths: Set<String>
        let sourceContent: [String]
    }

    public static func basis(for input: String, protected: Protected,
                             knownLiteralRanges: [Range<String.Index>]? = nil) -> Basis {
        let ranges = (knownLiteralRanges ?? protected.ranges(in: input, detect: false))
            .sorted { $0.lowerBound < $1.lowerBound }
        var previousUpper = input.startIndex
        var literals: [ProtectedSpan] = []
        literals.reserveCapacity(ranges.count)
        for span in ranges {
            let skip = span.lowerBound < previousUpper
            if !skip { previousUpper = span.upperBound }
            literals.append(ProtectedSpan(text: String(input[span]), skip: skip))
        }
        let segments = ListPlanner.plan(input, protected: protected)
        let comparable = segments.map { segment in
            switch segment {
            case .prose(let text): text
            case .list(let lead, let items): ([lead] + items).joined(separator: " ")
            }
        }.joined(separator: " ")
        let isList = segments.contains { if case .list = $0 { return true }; return false }
        // One tokenization and one content pass feed every downstream check.
        let sourceTokens = Tokenizer.tokens(in: comparable)
        // Paths and dotted identifiers still need an exact match; a modified
        // one ("hero.tsxbackup") must never pass as formatting.
        let pathLiterals = sourceTokens.filter {
            $0.core.contains(where: \.isNumber) || $0.core.contains("_") || $0.core.contains("/") || $0.core.contains(".")
        }.map(\.core)
        let allowsRevision = MeaningCarriers.hasRevisionCue(comparable)
        let sourceDigitCounts = counts(digitRuns(withoutEnumeration(comparable)))
        let sourceContent = content(comparable)
        let sourceSpeaksNumbers = sourceContent.contains { numberWords.contains($0) }
        let sourcePaths = Set(sourceTokens.map(\.core)
            .filter { $0.contains("/") && $0.contains(where: \.isLetter) }.map { $0.lowercased() })
        return Basis(protectedLiterals: literals, hasProtectedLiteral: !literals.isEmpty,
                     fillerOnly: FillerOnlyText.isFillerOnly(input), comparable: comparable,
                     isList: isList, pathLiterals: pathLiterals, allowsRevision: allowsRevision,
                     sourceDigitCounts: sourceDigitCounts, sourceContentWords: sourceContent,
                     sourceSpeaksNumbers: sourceSpeaksNumbers, sourcePaths: sourcePaths,
                     sourceContent: sourceContent)
    }

    /// Result-side guard only. All source scans happen once in `basis(for:)`.
    public static func verify(basis: Basis, result: CleanResult) -> Failure? {
        // Hitting the output cap is not, by itself, a rejection. S1-mini may use
        // every token and still return a complete cleanup. The content checks
        // below decide; a genuine loss is reported as `.truncated`, which the
        // service routes to split-and-retry instead of a raw-text fallback.
        let input = basis.comparable
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if basis.hasProtectedLiteral { return .protectedLost }
            return basis.fillerOnly ? nil : .empty
        }
        var cursor = result.text.startIndex
        for span in basis.protectedLiterals where !span.skip {
            guard let match = result.text.range(of: span.text, range: cursor..<result.text.endIndex),
                  boundary(result.text, match.lowerBound, before: true),
                  boundary(result.text, match.upperBound, before: false) else { return .protectedLost }
            cursor = match.upperBound
        }
        // Enumeration labels are formatting; numbers within items remain data.
        for literal in basis.pathLiterals where !literal.contains(where: \.isNumber) {
            guard let match = result.text.range(of: literal, options: .caseInsensitive,
                                                range: result.text.startIndex..<result.text.endIndex),
                  boundary(result.text, match.lowerBound, before: true),
                  boundary(result.text, match.upperBound, before: false) else { return .protectedLost }
        }
        // S1-mini renders quantities in written form ("200ms" -> "200 ms").
        // Compare whole digit runs so formatting passes but 500 -> 1500 fails.
        let sourceCounts = basis.sourceDigitCounts
        let resultCounts = counts(digitRuns(withoutEnumeration(result.text)))
        // Direction 1: every digit the source carried must survive.
        for (run, needed) in sourceCounts where (resultCounts[run] ?? 0) < needed { return .protectedLost }
        // Direction 2: an invented digit is data loss. Spoken number words
        // ("forty three" -> "43") and values landed on by an explicit revision
        // ("no sorry make that 43") legitimately introduce renders that were
        // not literal digits in the source, so only the source's own digits are
        // required in those cases.
        if !basis.sourceSpeaksNumbers && !basis.allowsRevision {
            for (run, needed) in resultCounts where (sourceCounts[run] ?? 0) < needed { return .protectedLost }
        }
        let outputPaths = Tokenizer.tokens(in: result.text).map(\.core)
            .filter { $0.contains("/") && $0.contains(where: \.isLetter) }.map { $0.lowercased() }
        // A model may legitimately COMPLETE a spoken path: Tier 0 stops at the
        // first path token ("lib/backend/.../prospect") while the model joins the
        // spoken "dash main dash engine dot t s" suffix into the same path. An
        // output path is accepted when it equals a source path or extends one at
        // a token boundary; a different or shortened path is still rejected.
        if !basis.sourcePaths.isEmpty {
            guard outputPaths.allSatisfy({ output in
                basis.sourcePaths.contains { source in
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
            let hasSpokenPath = Tokenizer.tokens(in: input)
                .contains { spokenSeparators.contains($0.core.lowercased()) }
            if !hasSpokenPath { return .contentChanged }
        }
        guard MeaningCarriers.accepts(input, result.text,
                                      allowsRevision: basis.allowsRevision) else { return .contentChanged }
        let source = basis.sourceContent
        let cleaned = content(result.text)
        guard !cleaned.isEmpty else { return .contentChanged }
        // S1-mini is a normalizer: grammar, false starts and explicit corrections
        // legitimately change word order and vocabulary. Exact lexical equality
        // rejects that work. Keep the hard data checks above and reject gross
        // loss — even for a revision, a self-correction must not erase most of
        // the utterance.
        if source.count > 12, cleaned.count * 2 < source.count { return .truncated }
        // Compare the WHOLE content-token multiset, not just the trailing word:
        // a dropped middle clause must be caught too. Number words and spoken
        // ordinal markers are layout (numeric rendering and list shaping are
        // owned downstream), so they are excluded from this comparison.
        let ordinalMarkers: Set<String> = [
            "first", "second", "third", "fourth", "fifth", "sixth",
            "seventh", "eighth", "ninth", "tenth",
        ]
        let sourceWords = basis.sourceContentWords.filter { !Self.numberWords.contains($0) && !ordinalMarkers.contains($0) }
        let cleanedWords = cleaned.filter { !Self.numberWords.contains($0) && !ordinalMarkers.contains($0) }
        var remaining = Self.counts(cleanedWords)
        var dropped = 0
        for word in sourceWords {
            if let available = remaining[word], available > 0 { remaining[word] = available - 1 }
            else { dropped += 1 }
        }
        // Revisions and list shaping legitimately discard lead-in words, so
        // give them a wider allowance; ordinary prose keeps a tight bound.
        let tolerance = (basis.allowsRevision || basis.isList)
            ? max(3, sourceWords.count / 2)
            : max(2, sourceWords.count / 6)
        if dropped > tolerance { return .truncated }
        // Tail loss (e.g. a chunked cleaner dropping the last word of a chunk)
        // is not caught by the count ratios; check the trailing word explicitly.
        // Pass hitTokenCap: false so a capped-but-complete result is still
        // evaluated here instead of short-circuiting to .hitTokenCap.
        let tailCheckedInput = input.split(whereSeparator: \.isWhitespace).reversed()
            .drop(while: { fillers.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) })
            .reversed().joined(separator: " ")
        if TruncationDetector().detect(input: tailCheckedInput, output: result.text,
                                       hitTokenCap: false,
                                       allowsRevision: basis.allowsRevision) == .missingTail {
            return .truncated
        }
        return nil
    }

    public static func verify(input: String, protected: Protected, result: CleanResult, cap: Int) -> Failure? {
        _ = cap // a capped-but-complete result is evaluated, not auto-rejected
        return verify(basis: basis(for: input, protected: protected), result: result)
    }

    /// Enumeration labels are layout, not data. Strip both inline markers
    /// ("Step 10") and numbered list markers ("1.", "2)") before comparing
    /// digits, so an S1-rendered numbered list is not read as invented values.
    private static func withoutEnumeration(_ text: String) -> String {
        let inline = text.replacingOccurrences(
            of: #"(?im)^\s*(?:step|item|number|point)\s+[0-9]+\s*"#,
            with: "", options: .regularExpression)
        return inline.replacingOccurrences(
            of: #"(?m)^\s*[0-9]+[.)]\s+"#,
            with: "", options: .regularExpression)
    }

    private static func counts(_ tokens: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for token in tokens { result[token, default: 0] += 1 }
        return result
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

    private static let numberWords: Set<String> = [
        "zero", "oh", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion",
    ]
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
