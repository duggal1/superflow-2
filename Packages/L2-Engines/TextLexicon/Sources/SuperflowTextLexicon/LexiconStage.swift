import Foundation
import SuperflowKernel
import SuperflowPorts

public struct LexiconWarning: Sendable, Equatable {
    public let trigger: String
    public let message: String
    public init(trigger: String, message: String) {
        self.trigger = trigger
        self.message = message
    }
}

/// Personal dictionary first, then the bundled tech dictionary.
/// Whole-token, case-insensitive matching through a character trie; multi-word
/// triggers are allowed, the longest match wins, and each line is rewritten in
/// a single pass. Terms normalize away case, spacing, hyphens, dots and the
/// spoken word "dot". Corrections map a model output form to the user's form.
public struct LexiconStage: ExplainingTextStage {
    public let id: String
    public let warnings: [LexiconWarning]
    public let entryCount: Int
    private let trie: LexiconTrie
    private let canonicals: [String]
    private let ruleIDs: [String]

    public init(entries: [LexiconEntry], id: String = "lexicon") {
        self.id = id
        let ordered = entries.filter { $0.enabled && !$0.canonical.isEmpty }
            .enumerated()
            .sorted { lhs, rhs in
                let lhsUser = lhs.element.source == .user
                let rhsUser = rhs.element.source == .user
                if lhsUser != rhsUser { return lhsUser }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        var trie = LexiconTrie()
        var canonicals: [String] = []
        var ruleIDs: [String] = []
        var owner: [String: Int] = [:]
        var seenWarnings = Set<String>()
        var warnings: [LexiconWarning] = []

        func warn(_ trigger: String, _ message: String) {
            guard seenWarnings.insert(message).inserted else { return }
            warnings.append(LexiconWarning(trigger: trigger, message: message))
        }

        for entry in ordered {
            var triggers = entry.triggers
            if entry.kind == .term { triggers.append(entry.canonical) }
            for trigger in triggers {
                let key = LexiconNormalizer.key(trigger)
                guard !key.isEmpty else { continue }
                if let existing = owner[key] {
                    let existingCanonical = canonicals[existing]
                    if existingCanonical != entry.canonical {
                        warn(trigger, "trigger \"\(trigger)\" maps to both \"\(existingCanonical)\" " +
                            "and \"\(entry.canonical)\"; keeping the first")
                    }
                    continue
                }
                owner[key] = canonicals.count
                canonicals.append(entry.canonical)
                ruleIDs.append(entry.id)
                trie.insert(Array(key), entry: canonicals.count - 1)
            }
            for trigger in triggers where CommonWords.isRisky(trigger: trigger) {
                warn(trigger, "trigger \"\(trigger)\" is made only of common English words " +
                    "and may rewrite normal speech")
            }
        }

        self.trie = trie
        self.canonicals = canonicals
        self.ruleIDs = ruleIDs
        self.entryCount = ordered.count
        self.warnings = warnings
    }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var output = draft
        var found = Set<String>()
        output.text = draft.text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { replaceLine(String($0), protected: draft.protected, found: &found) }
            .joined(separator: "\n")
        output.protected.literals.formUnion(found)
        for warning in warnings {
            let diagnostic = Diagnostic(stage: id, message: warning.message)
            if !output.diagnostics.contains(diagnostic) { output.diagnostics.append(diagnostic) }
        }
        return output
    }

    private func replaceLine(_ line: String, protected: Protected, found: inout Set<String>,
                             record: ((Range<String.Index>, String, String, Int) -> Void)? = nil) -> String {
        let stream = LexiconStream.build(line)
        guard !stream.tokens.isEmpty else { return line }
        let ranges = protected.ranges(in: line, detect: true)
        var out: [String] = []
        var outputUTF16 = 0

        func append(_ piece: String) -> Int {
            if !out.isEmpty { outputUTF16 += 1 }
            let start = outputUTF16
            out.append(piece)
            outputUTF16 += piece.utf16.count
            return start
        }

        var index = 0
        while index < stream.tokens.count {
            let start = stream.tokenStart[index]
            if start >= 0, let match = trie.longestMatch(in: stream, from: start) {
                let last = stream.endToken[match.end - 1]
                if last >= index {
                    let slice = stream.tokens[index...last]
                    let blocked = ranges.contains { range in
                        slice.contains { $0.range.overlaps(range) }
                    }
                    if !blocked {
                        let canonical = canonicals[match.entry]
                        let lead = stream.tokens[index].lead
                        let trail = stream.tokens[last].trail
                        let startOffset = append(lead + canonical + trail)
                        record?(stream.tokens[index].range.lowerBound..<stream.tokens[last].range.upperBound,
                                canonical, ruleIDs[match.entry], startOffset + lead.utf16.count)
                        found.insert(canonical)
                        index = last + 1
                        continue
                    }
                }
            }
            _ = append(stream.tokens[index].full)
            index += 1
        }
        return out.joined(separator: " ")
    }

    public func explainEdits(before: TranscriptDraft, after: TranscriptDraft,
                             context: TextContext) async -> [TextEdit]? {
        var found = Set<String>()
        var edits: [TextEdit] = []
        var rebuilt: [String] = []
        var inputLineStart = 0
        var outputLineStart = 0
        let lines = before.text.components(separatedBy: "\n")

        for (lineIndex, line) in lines.enumerated() {
            var recorded: [(TextSpan, TextSpan, String)] = []
            let rewritten = replaceLine(line, protected: before.protected, found: &found) {
                input, canonical, ruleID, outputStart in
                let local = NSRange(input, in: line)
                recorded.append((TextSpan(location: inputLineStart + local.location, length: local.length),
                                 TextSpan(location: outputLineStart + outputStart,
                                          length: canonical.utf16.count),
                                 ruleID))
            }
            rebuilt.append(rewritten)
            for (input, output, ruleID) in recorded {
                edits.append(TextEdit(stageID: id, ruleID: ruleID, kind: .replace,
                                      input: input, output: output))
            }
            inputLineStart += (line as NSString).length + (lineIndex < lines.count - 1 ? 1 : 0)
            outputLineStart += rewritten.utf16.count + (lineIndex < lines.count - 1 ? 1 : 0)
        }

        guard rebuilt.joined(separator: "\n") == after.text else { return nil }
        return edits.isEmpty ? nil : edits
    }
}
