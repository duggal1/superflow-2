import Foundation
import SuperflowKernel

/// Rewritten text plus the exact tokens that were removed.
public struct DisfluencyOutput: Sendable, Equatable {
    public var text: String
    public var edits: [TextEdit]
    public init(text: String, edits: [TextEdit]) {
        self.text = text
        self.edits = edits
    }
}

/// Deterministic, sub-millisecond disfluency pass.
///
/// Rules, in order:
/// 1. Drop only pure fillers. Content-bearing words ("like", "you know",
///    "I mean", "so") are never removed here; the cleanup model owns those.
/// 2. Collapse a repeated single word only when the tier allows it. Tier A
///    words collapse at two; Tier B words need three; unknown words, number
///    words and allowlisted repetitions are left for the model.
/// 3. Collapse an adjacent repeated 2-3 word phrase once. Protected spans,
///    code-like tokens and emails are never touched.
public enum DisfluencyRewriter {
    /// Legitimate repetitions that must survive every rule.
    static let allowlistedPhrases: Set<String> = [
        "bye bye", "ha ha", "blah blah",
    ]

    /// Words that are safe to collapse at two. Short function words only; a
    /// content word repeated twice is usually deliberate or needs context.
    static let tierA: Set<String> = [
        "the", "a", "an", "i", "to", "of", "in", "on", "and", "but", "it",
        "we", "you", "they", "he", "she", "my", "for", "with", "at",
    ]

    /// Words that can be a real double ("had had", "that that", "is is") and
    /// therefore collapse only at three.
    static let tierB: Set<String> = [
        "had", "that", "is", "was", "do", "can", "very", "so", "no", "really",
    ]

    /// Number words must never be collapsed: "twenty twenty-six" is a year,
    /// not a stutter.
    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty",
        "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
        "thousand", "million", "billion", "trillion", "dozen",
    ]

    /// Pure fillers. Elongations are recognized by `fillerBase` below.
    static let fillers: Set<String> = ["um", "uh", "uhm", "erm", "er", "hmm", "mmm", "ah"]

    public static func rewrite(_ text: String, protected: Protected,
                               settings: DisfluencySettings,
                               stageID: String = "disfluency") -> DisfluencyOutput {
        guard settings.enabled else { return DisfluencyOutput(text: text, edits: []) }
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var edits: [TextEdit] = []
        var inputLineStart = 0
        var outputLineStart = 0

        for (lineIndex, line) in lines.enumerated() {
            let isLast = lineIndex == lines.count - 1
            let rewritten = rewriteLine(line, protected: protected, settings: settings,
                                        stageID: stageID, inputLineStart: inputLineStart,
                                        outputLineStart: outputLineStart, edits: &edits)
            out.append(rewritten)
            inputLineStart += line.utf16.count + (isLast ? 0 : 1)
            outputLineStart += rewritten.utf16.count + (isLast ? 0 : 1)
        }
        return DisfluencyOutput(text: out.joined(separator: "\n"), edits: edits)
    }

    private static func rewriteLine(_ line: String, protected: Protected,
                                    settings: DisfluencySettings, stageID: String,
                                    inputLineStart: Int, outputLineStart: Int,
                                    edits: inout [TextEdit]) -> String {
        let tokens = Tokenizer.tokens(in: line)
        guard !tokens.isEmpty else { return line }
        let ranges = protected.ranges(in: line, detect: true)
        var keep = [Bool](repeating: true, count: tokens.count)

        func isProtected(_ index: Int) -> Bool {
            ranges.contains { $0.overlaps(tokens[index].range) }
        }

        if settings.fillerPrepass {
            for index in tokens.indices where !isProtected(index) {
                if fillerBase(tokens[index].core, tokens: tokens, at: index) != nil {
                    keep[index] = false
                }
            }
        }

        if settings.collapseDuplicates {
            var runWord: String?
            var run: [Int] = []
            func flushRun() {
                defer {
                    run.removeAll(keepingCapacity: true)
                    runWord = nil
                }
                guard let word = runWord, run.count >= threshold(for: word, settings: settings) else {
                    return
                }
                for index in run.dropFirst() { keep[index] = false }
            }
            for index in tokens.indices {
                // A filler that is already deleted does not break the run: the
                // text the user hears is contiguous once the filler is gone.
                guard keep[index] else { continue }
                // Punctuation, protected spans, code and number words are real
                // boundaries. Without this, "the . the" would collapse even
                // though the two words are not adjacent.
                guard !isProtected(index), let word = eligibleWord(tokens[index]) else {
                    flushRun()
                    continue
                }
                if word == runWord {
                    run.append(index)
                } else {
                    flushRun()
                    runWord = word
                    run = [index]
                }
            }
            flushRun()

            if settings.collapseRepeatedPhrases {
                collapseRepeatedPhrases(tokens, keep: &keep, isProtected: isProtected,
                                        maxWords: 3, settings: settings)
            }
        }

        // No deletion means this pass has nothing to improve. Return the input
        // byte for byte instead of re-joining tokens and normalizing spacing.
        guard keep.contains(false) else { return line }

        var pieces: [String] = []
        var outputUTF16 = 0
        for index in tokens.indices where keep[index] {
            if !pieces.isEmpty { outputUTF16 += 1 } // the joining space
            pieces.append(tokens[index].full)
            outputUTF16 += tokens[index].full.utf16.count
        }

        // Deleted tokens carry provenance in a separate pass so output offsets
        // stay identical to the text this stage actually emits.
        var emittedUTF16 = 0
        var emittedCount = 0
        for index in tokens.indices {
            if keep[index] {
                if emittedCount > 0 { emittedUTF16 += 1 }
                emittedUTF16 += tokens[index].full.utf16.count
                emittedCount += 1
                continue
            }
            let rule = settings.fillerPrepass
                && fillerBase(tokens[index].core, tokens: tokens, at: index) != nil
                ? "filler" : "duplicate"
            recordDelete(tokens[index], line: line, stageID: stageID, ruleID: rule,
                         inputLineStart: inputLineStart,
                         outputUTF16: outputLineStart + emittedUTF16, edits: &edits)
        }

        // A line that is only a filler stays as dictated so the pipeline never
        // turns a non-empty segment into empty text.
        guard !pieces.isEmpty else { return line }
        return pieces.joined(separator: " ")
    }

    private static func recordDelete(_ token: Token, line: String, stageID: String, ruleID: String,
                                     inputLineStart: Int, outputUTF16: Int,
                                     edits: inout [TextEdit]) {
        let local = NSRange(token.range, in: line)
        edits.append(TextEdit(
            stageID: stageID, ruleID: ruleID, kind: .delete,
            input: TextSpan(location: inputLineStart + local.location, length: local.length),
            output: TextSpan(location: outputUTF16, length: 0)))
    }

    /// Collapses an immediately repeated phrase of two or three words. The
    /// first occurrence stays, so "we need to we need to go" becomes "we need
    /// to go". Runs of one word are handled by the tiered rule above.
    private static func collapseRepeatedPhrases(_ tokens: [Token], keep: inout [Bool],
                                                isProtected: (Int) -> Bool,
                                                maxWords: Int, settings: DisfluencySettings) {
        var index = 0
        while index < tokens.count {
            guard keep[index], !isProtected(index), eligibleWord(tokens[index]) != nil else {
                index += 1
                continue
            }
            var collapsed = false
            for length in stride(from: max(2, maxWords), through: 2, by: -1) {
                let second = index + length
                guard second + length <= tokens.count else { continue }
                guard phraseMatches(tokens, first: index, second: second, length: length,
                                    keep: keep, isProtected: isProtected,
                                    settings: settings) else { continue }
                let words = (0..<length).compactMap { eligibleWord(tokens[index + $0]) }
                guard words.count == length,
                      !allowlistedPhrases.contains(words.joined(separator: " ")) else { continue }
                for offset in 0..<length { keep[second + offset] = false }
                index += length
                collapsed = true
                break
            }
            if !collapsed { index += 1 }
        }
    }

    private static func phraseMatches(_ tokens: [Token], first: Int, second: Int, length: Int,
                                      keep: [Bool], isProtected: (Int) -> Bool,
                                      settings: DisfluencySettings) -> Bool {
        for offset in 0..<length {
            let a = first + offset
            let b = second + offset
            guard keep[a], keep[b], !isProtected(a), !isProtected(b),
                  let left = eligibleWord(tokens[a]), let right = eligibleWord(tokens[b]),
                  left == right, !numberWords.contains(left) else {
                return false
            }
        }
        return true
    }

    /// How many repeats are needed before this word loses all but the first.
    /// `Int.max` means never: the model owns that judgement.
    static func threshold(for word: String, settings: DisfluencySettings) -> Int {
        if allowlistedPhrases.contains(word) || numberWords.contains(word) {
            return Int.max
        }
        if tierA.contains(word) {
            return max(2, settings.tierAThreshold)
        }
        if tierB.contains(word) {
            return max(3, settings.tierBThreshold)
        }
        return Int.max
    }

    /// A word the duplicate rules may touch. Punctuation-only tokens, emails,
    /// paths, filenames and numeric tokens are boundaries instead of words.
    static func eligibleWord(_ token: Token) -> String? {
        let value = token.core.lowercased()
        guard !value.isEmpty else { return nil }
        guard value.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return nil }
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Case-insensitive core used for diagnostics. Kept for callers that only
    /// need a normalized token, not the eligibility rules.
    static func normalizedCore(_ core: String) -> String? {
        let value = core.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters)
        return value.isEmpty ? nil : value
    }

    /// Returns the canonical filler for a standalone token, or nil. Ordinary
    /// English words are never fillers here.
    static func fillerBase(_ core: String, tokens: [Token], at index: Int) -> String? {
        let word = core.lowercased()
        guard !word.isEmpty, word.allSatisfy(\.isLetter), word.count <= 6 else { return nil }
        if fillers.contains(word) {
            if word == "ah", ahIsContent(tokens, at: index) { return nil }
            return word
        }
        let base: String
        switch word {
        case let w where w.hasPrefix("umm") && w.dropFirst(2).allSatisfy({ $0 == "m" }): base = "um"
        case let w where w.hasPrefix("uhh") && w.dropFirst(2).allSatisfy({ $0 == "h" }): base = "uh"
        case let w where w.hasPrefix("hmmm") && w.dropFirst(3).allSatisfy({ $0 == "m" }): base = "hmm"
        case let w where w.hasPrefix("ermm") && w.dropFirst(3).allSatisfy({ $0 == "m" }): base = "erm"
        case let w where w.hasPrefix("err") && w.dropFirst(2).allSatisfy({ $0 == "r" }): base = "er"
        case let w where w.hasPrefix("ahh") && w.dropFirst(2).allSatisfy({ $0 == "h" }): base = "ah"
        default: return nil
        }
        guard fillers.contains(base) else { return nil }
        if base == "ah", ahIsContent(tokens, at: index) { return nil }
        return base
    }

    /// "ah ha" and "ah yes" are content, not a filler.
    private static func ahIsContent(_ tokens: [Token], at index: Int) -> Bool {
        let next = index + 1 < tokens.count ? tokens[index + 1].core.lowercased() : ""
        return next == "ha" || next == "yes"
    }
}
