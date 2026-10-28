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
/// Two rules only:
/// 1. Collapse runs of identical consecutive tokens (case-insensitive) once
///    the run reaches `duplicateThreshold`. Protected spans are never touched.
/// 2. Optionally drop standalone high-frequency fillers. Content-bearing words
///    ("like", "you know", "I mean", "well", "so") are never removed here; the
///    specialized cleanup model owns contextual filler removal.
public enum DisfluencyRewriter {
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
                if run.count >= max(2, settings.duplicateThreshold) {
                    for index in run.dropFirst() { keep[index] = false }
                }
                run.removeAll(keepingCapacity: true)
                runWord = nil
            }
            for index in tokens.indices {
                // A filler that is already deleted does not break the run: the
                // text the user hears is contiguous once the filler is gone.
                guard keep[index] else { continue }
                // Punctuation, protected spans and other non-words are real
                // boundaries. Without this, "the . the" would collapse even
                // though the two words are not adjacent.
                guard !isProtected(index), let word = normalizedCore(tokens[index].core) else {
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

    /// Case-insensitive core used for duplicate comparison. Punctuation-only
    /// tokens never participate, so a comma between repeated words is kept.
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
