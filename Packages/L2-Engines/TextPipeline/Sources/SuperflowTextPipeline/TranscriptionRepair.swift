import Foundation
import SuperflowKernel
import SuperflowPorts

/// Deterministic transcript repair that needs no model: sentence-boundary
/// spacing, doubled-capital ASR artifacts, and exact repeated sentences.
/// Conservative by design: it only removes mechanically identifiable noise,
/// never rewrites meaning, numbers, or names.
enum TranscriptionRepair: Sendable {
    static func apply(_ input: String, protected: Protected = Protected()) -> String {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return input }
        var text = input
        text = repairMissingSpaceAfterPunctuation(text)
        text = repairDoubledCapital(text, protected: protected)
        text = removeRepeatedSentences(text)
        text = collapseExcessSpaces(text)
        return text
    }

    /// "you.Hey" → "you. Hey". Only when an uppercase letter follows terminal
    /// punctuation with no space. Lowercase continuations stay glued, so
    /// "Next.js" and "hero.tsx" are never split.
    private static func repairMissingSpaceAfterPunctuation(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count + 8)
        var previous: Character?
        for character in input {
            if let prev = previous, isTerminator(prev),
               character.isLetter, character.isUppercase {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }
        return result
    }

    private static func isTerminator(_ character: Character) -> Bool {
        character == "." || character == "?" || character == "!" || character == "…"
    }

    /// "II think" → "I think" at a word boundary. Only the exact standalone
    /// "II" token; never touches "II" inside words or protected literals.
    private static func repairDoubledCapital(_ input: String, protected: Protected) -> String {
        var lines: [String] = []
        for line in input.components(separatedBy: "\n") {
            lines.append(repairLineDoubledCapital(line, protected: protected))
        }
        return lines.joined(separator: "\n")
    }

    private static func repairLineDoubledCapital(_ line: String, protected: Protected) -> String {
        let ns = line as NSString
        let protectedRanges: [NSRange] = protected.ranges(in: line).map { NSRange($0, in: line) }
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])II(?![\p{L}\p{N}])"#) else { return line }
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return line }
        var output = ""
        var cursor = 0
        for match in matches {
            if protectedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += "I"
            cursor = NSMaxRange(match.range)
        }
        output += ns.substring(from: cursor)
        return output
    }

    /// Exact repeated sentences back-to-back ("X. X.") keep one copy. Only
    /// consecutive duplicates, case-insensitive, punctuation-normalized.
    private static func removeRepeatedSentences(_ input: String) -> String {
        var outputLines: [String] = []
        for line in input.components(separatedBy: "\n") {
            outputLines.append(removeRepeatedSentencesInLine(line))
        }
        return outputLines.joined(separator: "\n")
    }

    private static func splitSentences(_ line: String) -> [(text: String, sep: String)] {
        var sentences: [(String, String)] = []
        var current = ""
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            current.append(character)
            let next = line.index(after: index)
            if isTerminator(character), (next == line.endIndex || line[next].isWhitespace) {
                var sep = ""
                var cursor = next
                while cursor < line.endIndex, line[cursor].isWhitespace {
                    sep.append(line[cursor])
                    cursor = line.index(after: cursor)
                }
                sentences.append((String(current).trimmingCharacters(in: .whitespaces), sep))
                current = ""
                index = cursor
                continue
            }
            index = next
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append((current.trimmingCharacters(in: .whitespaces), ""))
        }
        return sentences
    }

    private static func normalizeSentenceKey(_ sentence: String) -> String {
        sentence.lowercased()
            .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeRepeatedSentencesInLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return line }
        let sentences = splitSentences(line)
        guard sentences.count > 1 else { return line }
        var kept: [(String, String)] = []
        for sentence in sentences {
            if let last = kept.last, normalizeSentenceKey(last.0) == normalizeSentenceKey(sentence.0),
               !sentence.0.trimmingCharacters(in: .punctuationCharacters).isEmpty {
                continue
            }
            kept.append(sentence)
        }
        if kept.count == sentences.count { return line }
        return kept.map { $0.0 + $0.1 }.joined().trimmingCharacters(in: .whitespaces)
    }

    private static func collapseExcessSpaces(_ input: String) -> String {
        input.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }
}

struct TranscriptionRepairStage: SuperflowPorts.TextStage {
    let id: String
    init(id: String = "transcriptionRepair") { self.id = id }

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        output.text = TranscriptionRepair.apply(draft.text, protected: draft.protected)
        return output
    }
}

struct PreCleanupModelNameStage: SuperflowPorts.TextStage {
    let id = "preCleanupModelNames"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        let normalized = ModelNameNormalizer.normalize(draft.text, protected: draft.protected)
        output.text = normalized.text
        output.protected.literals.formUnion(normalized.literals)
        return output
    }
}
