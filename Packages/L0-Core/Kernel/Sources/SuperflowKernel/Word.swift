import Foundation

public struct Word: Equatable, Sendable, Hashable {
    public var lead: String
    public var core: String
    public var trail: String
    public var isProtected: Bool
    public var glue: Bool
    public var pauseBefore: Duration?
    // Legacy fields kept for existing callers.
    public var protected: Bool {
        get { isProtected }
        set { isProtected = newValue }
    }
    public var pause: Bool

    public init(lead: String = "", core: String, trail: String = "",
                isProtected: Bool = false, glue: Bool = false, pauseBefore: Duration? = nil,
                pause: Bool = false) {
        self.lead = lead
        self.core = core
        self.trail = trail
        self.isProtected = isProtected
        self.glue = glue
        self.pauseBefore = pauseBefore
        self.pause = pause
    }

    // Legacy positional initializer.
    public init(_ core: String, lead: String = "", trail: String = "",
                protected: Bool = false, glue: Bool = false, pause: Bool = false) {
        self.lead = lead
        self.core = core
        self.trail = trail
        self.isProtected = protected
        self.glue = glue
        self.pauseBefore = nil
        self.pause = pause
    }

    private static let currencySymbols: Set<Character> = ["$", "€", "£", "₹"]

    public var text: String { lead + core + trail }
    public var key: String { core.lowercased().replacingOccurrences(of: "’", with: "'") }
    public var endsSentence: Bool { trail.contains { ".!?…".contains($0) } }
    public var sentenceEnd: Bool { endsSentence }
    public var hardBreak: Bool { trail.contains { ",;:.?!".contains($0) } }

    /// Canonical form used by the protected-literal guard.
    public var literal: String {
        lead.filter { Self.currencySymbols.contains($0) } + core + trail.prefix(while: { $0 == "%" })
    }

    public static func parse(_ token: String) -> Word {
        let chars = Array(token)
        guard let first = chars.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let last = chars.lastIndex(where: { $0.isLetter || $0.isNumber }) else {
            return Word(lead: token, core: "")
        }
        return Word(lead: String(chars[..<first]),
                    core: String(chars[first...last]),
                    trail: String(chars[(last + 1)...]))
    }

    public static func tokenize(_ text: String) -> [Word] {
        text.split(whereSeparator: \.isWhitespace).map { parse(String($0)) }
    }

    public static func merged(_ core: String, from first: Word, to last: Word, protected: Bool) -> Word {
        Word(core, lead: first.lead, trail: last.trail, protected: protected,
             glue: last.glue, pause: last.pause)
    }
}

public extension Tokenizer {
    static func words(_ text: String, protected: Protected = Protected()) -> [Word] {
        let slices = text.split(whereSeparator: \.isWhitespace)
        var spans: [Range<String.Index>] = []
        for range in protected.ranges(in: text).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let previous = spans.last, range.lowerBound <= previous.upperBound {
                spans[spans.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
            } else {
                spans.append(range)
            }
        }
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
            word.isProtected = word.core.contains(where: \.isNumber)
                || word.core.contains(where: { "/_@".contains($0) })
                || (word.core.contains(".") && word.core.contains(where: \.isLetter))
            while spanIndex < spans.count, spans[spanIndex].upperBound <= slice.startIndex { spanIndex += 1 }
            var index = spanIndex
            while index < spans.count, spans[index].lowerBound < slice.endIndex {
                let span = spans[index]
                if span.overlaps(slice.startIndex..<slice.endIndex) {
                    word.isProtected = true
                    if position + 1 < slices.count, span.upperBound > slices[position + 1].startIndex {
                        word.glue = true
                    }
                }
                index += 1
            }
            // keep legacy field in sync
            word.protected = word.isProtected
            return word
        }
    }

    static func join<S: Sequence>(_ words: S) -> String where S.Element == Word {
        words.map(\.text).joined(separator: " ")
    }
}
