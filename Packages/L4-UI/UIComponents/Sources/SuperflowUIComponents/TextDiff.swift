import Foundation

/// Word-level diff for the debugging views (History's Raw mode and the
/// Dictionary playground). A windowed LCS keeps it linear enough for a long
/// transcript while still catching local edits, which is exactly what cleanup,
/// dictionary and shortcut stages produce.
public enum TextDiff {
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let changed: Bool

        public init(text: String, changed: Bool) {
            self.text = text
            self.changed = changed
        }
    }

    private struct Word {
        let word: String
        let trailing: String
        var text: String { word + trailing }
    }

    /// Marks each word of `candidate` that has no counterpart in `reference`.
    /// Separators are preserved, so the rendered text is the input text.
    public static func segments(reference: String, candidate: String, window: Int = 32) -> [Segment] {
        let referenceWords = tokenize(reference)
        let candidateWords = tokenize(candidate)
        guard !candidateWords.isEmpty else { return [] }
        guard !referenceWords.isEmpty else {
            return candidateWords.map { Segment(text: $0.text, changed: true) }
        }

        var changed = [Bool](repeating: true, count: candidateWords.count)
        var referenceIndex = 0

        for candidateIndex in candidateWords.indices {
            let windowEnd = min(candidateIndex + max(1, window), candidateWords.count)
            let needle = candidateWords[candidateIndex].word
            if let match = find(needle, in: referenceWords, from: referenceIndex, until: windowEnd) {
                changed[candidateIndex] = false
                referenceIndex = match + 1
            }
        }

        return zip(candidateWords, changed).map { Segment(text: $0.0.text, changed: $0.1) }
    }

    private static func find(_ needle: String, in words: [Word], from start: Int,
                             until windowEnd: Int) -> Int? {
        var index = start
        let limit = windowEnd - start
        var scanned = 0
        while index < words.count, scanned < limit {
            if words[index].word.caseInsensitiveCompare(needle) == .orderedSame { return index }
            index += 1
            scanned += 1
        }
        return nil
    }

    private static func tokenize(_ text: String) -> [Word] {
        var words: [Word] = []
        var current = ""
        var trailing = ""
        var inTrailing = false
        for character in text {
            if character.isWhitespace || character.isNewline {
                inTrailing = true
                trailing.append(character)
            } else {
                if inTrailing {
                    words.append(Word(word: current, trailing: trailing))
                    current = ""
                    trailing = ""
                    inTrailing = false
                }
                current.append(character)
            }
        }
        if !current.isEmpty || !trailing.isEmpty {
            words.append(Word(word: current, trailing: trailing))
        }
        return words
    }
}
