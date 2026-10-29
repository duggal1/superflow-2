import Foundation
import SuperflowKernel
import SuperflowPorts

public enum CleanGuard {
    public enum Failure: String, Error, Sendable { case truncated, protectedLost, contentChanged, empty }

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
        // Numbers and filenames are data even when a caller has not marked them.
        let data = Tokenizer.tokens(in: input).filter {
            $0.core.contains(where: \.isNumber) || $0.core.contains("_") || $0.core.contains("/") || $0.core.contains(".")
        }.map(\.core)
        cursor = result.text.startIndex
        for literal in data {
            guard let match = result.text.range(of: literal, options: .caseInsensitive, range: cursor..<result.text.endIndex),
                  boundary(result.text, match.lowerBound, before: true),
                  boundary(result.text, match.upperBound, before: false) else { return .protectedLost }
            cursor = match.upperBound
        }
        return content(input) == content(result.text) ? nil : .contentChanged
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
        let words = text.split(whereSeparator: \.isWhitespace).map {
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
