import Foundation
import SuperflowKernel

public struct ParagraphRules: Sendable, Equatable {
    public var minWords: Int
    public var preferredWords: Int
    public var maxWords: Int
    public init(minWords: Int = 25, preferredWords: Int = 35, maxWords: Int = 45) {
        self.minWords = minWords
        self.preferredWords = preferredWords
        self.maxWords = maxWords
    }
}

public enum ParagraphShaper {
    public static func apply(_ text: String, rules: ParagraphRules = ParagraphRules()) -> String {
        text.components(separatedBy: "\n\n")
            .map { shape($0, rules) }
            .joined(separator: "\n\n")
    }

    private static func shape(_ block: String, _ rules: ParagraphRules) -> String {
        // Lists, code and any already multi-line block keep their own shape.
        if block.contains("\n") || block.hasPrefix("```") || startsWithListMarker(block) {
            return block
        }
        let split = SentenceSplitter.split(block)
        var sentences = split.complete
        if !split.remainder.isEmpty { sentences.append(split.remainder) }
        guard wordCount(block) > rules.maxWords, sentences.count > 1 else { return block }

        var paragraphs: [[String]] = [[]]
        var words = 0
        for sentence in sentences {
            let count = wordCount(sentence)
            if words >= rules.minWords, words >= rules.preferredWords || words + count > rules.maxWords {
                paragraphs.append([])
                words = 0
            }
            paragraphs[paragraphs.count - 1].append(sentence)
            words += count
        }
        if paragraphs.count > 1 {
            let tail = paragraphs[paragraphs.count - 1].reduce(0) { $0 + wordCount($1) }
            if tail < 8 {
                let removed = paragraphs.removeLast()
                paragraphs[paragraphs.count - 1].append(contentsOf: removed)
            }
        }
        return paragraphs.map { $0.joined(separator: " ") }.joined(separator: "\n\n")
    }

    /// A block that already begins with a list marker is a list, not prose to reflow.
    private static func startsWithListMarker(_ block: String) -> Bool {
        block.range(of: #"^\s*([-*•]|\d{1,2}[.)])\s+"#, options: .regularExpression) != nil
    }
}

public enum Whitespace {
    /// Structure only: no trailing spaces, at most one blank line between blocks.
    public static func tidy(_ s: String) -> String {
        var text = s.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
