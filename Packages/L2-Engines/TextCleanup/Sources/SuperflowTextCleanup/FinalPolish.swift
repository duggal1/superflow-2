import Foundation
import SuperflowKernel
import SuperflowPorts

public enum FinalPolish {
    public static func text(_ input: String, protected: Protected = Protected()) -> String {
        let text = dates(input, protected: protected)
        let ranges = protected.ranges(in: text).sorted { $0.lowerBound < $1.lowerBound }
        var cursor = text.startIndex
        var output = ""
        for range in ranges where range.lowerBound >= cursor {
            output += tidy(String(text[cursor..<range.lowerBound]))
            output += text[range]
            cursor = range.upperBound
        }
        output += tidy(String(text[cursor...]))
        return output
    }

    private static func dates(_ text: String, protected: Protected) -> String {
        let pattern = "(?i)\\b(january|february|march|april|may|june|july|august|september|october|november|december) (\\d{1,2}) (\\d{4})\\b"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let protectedRanges = protected.ranges(in: text, detect: false)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var output = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text),
                  !protectedRanges.contains(where: { $0.overlaps(range) }),
                  let year = Range(match.range(at: 3), in: text) else { continue }
            output.insert(",", at: text.index(before: year.lowerBound))
        }
        return output
    }

    private static func tidy(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: " +([,.;:!?%])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?<![\\w./@_-])i(?=[ ',.;:!?]|$)", with: "I", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)\\b(january|february|march|april|may|june|july|august|september|october|november|december) (\\d{1,2}) (\\d{4})\\b", with: "$1 $2, $3", options: .regularExpression)
        let tokens = Tokenizer.tokens(in: result)
        var changes: [(Range<String.Index>, String)] = []
        for index in tokens.indices.dropFirst() {
            let previous = tokens[index - 1]
            let next = tokens[index]
            guard previous.trail.contains(where: { ".?!".contains($0) }),
                  !SentenceSplitter.abbreviationLike(previous.full),
                  let first = next.core.first, first.isLowercase else { continue }
            changes.append((next.range, next.lead + first.uppercased() + next.core.dropFirst() + next.trail))
        }
        for (range, replacement) in changes.reversed() { result.replaceSubrange(range, with: replacement) }
        return result
    }
}

private extension SentenceSplitter {
    static func abbreviationLike(_ text: String) -> Bool {
        let core = text.trimmingCharacters(in: CharacterSet.punctuationCharacters).lowercased()
        return ["dr", "mr", "mrs", "ms", "prof", "e.g", "i.e", "etc", "vs", "sr", "jr"].contains(core)
            || (core.count == 1 && core.first?.isLetter == true)
    }
}

public struct FinalPolishStage: SuperflowPorts.TextStage {
    public let id = "polish"
    public init() {}
    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var output = draft
        output.text = FinalPolish.text(draft.text, protected: draft.protected)
        return output
    }
}
