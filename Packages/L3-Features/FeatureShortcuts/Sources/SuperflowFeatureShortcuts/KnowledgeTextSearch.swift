import Foundation

/// Mirrors the SQLite FTS semantics for view-model consumers: tokenised,
/// multi-term AND, case/diacritic-insensitive, deterministically ranked.
enum KnowledgeTextSearch {
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Nil means no match; zero means an empty query, which matches everything.
    static func score(query: String, fields: [String]) -> Int? {
        let terms = tokens(query)
        guard !terms.isEmpty else { return 0 }
        var total = 0
        for term in terms {
            let needle = fold(term)
            var best = 0
            for (index, field) in fields.enumerated() {
                let haystack = fold(field)
                guard let range = haystack.range(of: needle) else { continue }
                var value = 10
                if range.lowerBound == haystack.startIndex { value += 5 }
                if index == 0 { value += 3 }
                best = max(best, value)
            }
            guard best > 0 else { return nil }
            total += best
        }
        return total
    }
}

enum KnowledgePlainTextCodec {
    static func escape(_ value: String) -> String {
        var out = ""
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case "=": out += "\\="
            case ">": out += "\\>"
            case "|": out += "\\|"
            case ",": out += "\\,"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out
    }

    static func unescape(_ value: String) -> String {
        var out = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "\\" {
                let next = value.index(after: index)
                if next < value.endIndex {
                    switch value[next] {
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    default: out.append(value[next])
                    }
                    index = value.index(after: next)
                    continue
                }
            }
            out.append(character)
            index = value.index(after: index)
        }
        return out
    }

    static func firstUnescaped(_ delimiter: String, in value: String) -> Range<String.Index>? {
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "\\" {
                index = value.index(after: index)
                if index < value.endIndex { index = value.index(after: index) }
                continue
            }
            if value[index...].hasPrefix(delimiter) {
                return index..<value.index(index, offsetBy: delimiter.count)
            }
            index = value.index(after: index)
        }
        return nil
    }

    static func splitUnescaped(_ value: String, by separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "\\" {
                let next = value.index(after: index)
                if next < value.endIndex {
                    current.append(character)
                    current.append(value[next])
                    index = value.index(after: next)
                    continue
                }
            }
            if character == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = value.index(after: index)
        }
        parts.append(current)
        return parts
    }
}
