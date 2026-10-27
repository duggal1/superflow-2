import Foundation

/// One whitespace-delimited chunk of speech, split into surrounding
/// punctuation and the core word. The leading whitespace is kept verbatim so
/// rebuilding an untouched string is byte-identical.
struct SpeakChunk: Equatable {
    let leading: String
    let prefix: String
    let core: String
    let suffix: String
    let range: Range<String.Index>

    var text: String { leading + prefix + core + suffix }

    func merged(core newCore: String, through last: SpeakChunk) -> SpeakChunk {
        SpeakChunk(leading: leading, prefix: prefix, core: newCore, suffix: last.suffix,
                   range: range.lowerBound..<last.range.upperBound)
    }
}

enum CodeSpeakParser {
    private static let edgePunctuation = CharacterSet(charactersIn: ".,!?;:()[]{}<>\"'“”‘’…")

    static func parse(_ text: String) -> [SpeakChunk] {
        var chunks: [SpeakChunk] = []
        var index = text.startIndex

        while index < text.endIndex {
            let whitespaceStart = index
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            let leading = String(text[whitespaceStart..<index])
            guard index < text.endIndex else {
                if !leading.isEmpty {
                    chunks.append(SpeakChunk(leading: leading, prefix: "", core: "", suffix: "",
                                             range: index..<index))
                }
                break
            }

            let chunkStart = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let raw = String(text[chunkStart..<index])
            let (prefix, core, suffix) = split(raw)
            chunks.append(SpeakChunk(leading: leading, prefix: prefix, core: core, suffix: suffix,
                                     range: chunkStart..<index))
        }
        return chunks
    }

    private static func split(_ raw: String) -> (String, String, String) {
        let characters = Array(raw)
        var first = 0
        var last = characters.count
        while first < last, String(characters[first]).rangeOfCharacter(from: edgePunctuation) != nil {
            first += 1
        }
        while last > first, String(characters[last - 1]).rangeOfCharacter(from: edgePunctuation) != nil {
            last -= 1
        }
        return (String(characters[0..<first]),
                String(characters[first..<last]),
                String(characters[last...]))
    }

    static func isWord(_ core: String) -> Bool {
        !core.isEmpty && core.contains { $0.isLetter || $0.isNumber }
    }

    static func isSeparator(_ core: String) -> Bool {
        separator(core) != nil
    }

    static func separator(_ core: String) -> String? {
        switch core.lowercased() {
        case "slash": return "/"
        case "backslash": return "\\"
        case "dot": return "."
        default: return nil
        }
    }

    static func subwords(_ core: String) -> [String] {
        var out: [String] = []
        var current = ""
        var previousWasLower = false
        for character in core {
            if character.isLetter || character.isNumber {
                if character.isUppercase, previousWasLower, !current.isEmpty {
                    out.append(current)
                    current = ""
                }
                current.append(character)
                previousWasLower = character.isLowercase
            } else {
                if !current.isEmpty {
                    out.append(current)
                    current = ""
                }
                previousWasLower = false
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func isCodeLike(_ core: String) -> Bool {
        guard !core.isEmpty else { return false }
        if core.contains("_") || core.contains("/") || core.contains(".") { return true }
        if core.contains(where: \.isNumber) { return true }
        let letters = Array(core)
        if letters.count > 1, letters.dropFirst().contains(where: \.isUppercase) { return true }
        return false
    }
}
