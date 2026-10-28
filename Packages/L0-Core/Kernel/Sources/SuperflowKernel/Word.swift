import Foundation

public struct Word: Equatable, Sendable {
    public var lead: String
    public var core: String
    public var trail: String
    public var protected: Bool
    public var glue: Bool
    public var pause: Bool

    public init(_ core: String, lead: String = "", trail: String = "",
                protected: Bool = false, glue: Bool = false, pause: Bool = false) {
        self.core = core
        self.lead = lead
        self.trail = trail
        self.protected = protected
        self.glue = glue
        self.pause = pause
    }

    public var key: String { core.lowercased().replacingOccurrences(of: "’", with: "'") }
    public var hardBreak: Bool { trail.contains { ",;:.?!".contains($0) } }
    public var sentenceEnd: Bool { trail.contains { ".?!".contains($0) } }
    public var text: String { lead + core + trail }

    public static func merged(_ core: String, from first: Word, to last: Word, protected: Bool) -> Word {
        Word(core, lead: first.lead, trail: last.trail, protected: protected,
             glue: last.glue, pause: last.pause)
    }
}

public extension Tokenizer {
    static func words(_ text: String, protected: Protected = Protected()) -> [Word] {
        let slices = text.split(whereSeparator: \.isWhitespace)
        let spans = protected.ranges(in: text).sorted { $0.lowerBound < $1.lowerBound }
        var spanIndex = 0
        let leads = Set<Character>("(\"'“‘[{")
        let trails = Set<Character>(".,;:!?)\"'”’…]}")
        return slices.enumerated().map { position, slice in
            var start = slice.startIndex
            var end = slice.endIndex
            while start < end, leads.contains(slice[start]) { start = slice.index(after: start) }
            while end > start, trails.contains(slice[slice.index(before: end)]) { end = slice.index(before: end) }
            var word: Word
            if start == end {
                word = Word(String(slice))
            } else {
                word = Word(String(slice[start..<end]), lead: String(slice[..<start]), trail: String(slice[end...]))
            }
            word.protected = word.core.contains(where: \.isNumber)
                || word.core.contains(where: { "/_@".contains($0) })
                || (word.core.contains(".") && word.core.contains(where: \.isLetter))
            while spanIndex < spans.count, spans[spanIndex].upperBound <= slice.startIndex { spanIndex += 1 }
            var index = spanIndex
            while index < spans.count, spans[index].lowerBound < slice.endIndex {
                let span = spans[index]
                if span.overlaps(slice.startIndex..<slice.endIndex) {
                    word.protected = true
                    if position + 1 < slices.count, span.upperBound > slices[position + 1].startIndex {
                        word.glue = true
                    }
                }
                index += 1
            }
            return word
        }
    }

    static func join<S: Sequence>(_ words: S) -> String where S.Element == Word {
        words.map(\.text).joined(separator: " ")
    }
}
