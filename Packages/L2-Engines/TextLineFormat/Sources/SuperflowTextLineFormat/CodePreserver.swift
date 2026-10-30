import Foundation

/// Masks inline code and code-shaped tokens before line formatting and puts
/// them back byte-for-byte afterwards. The formatter must never capitalize a
/// command, insert a space inside a path, or split a filename at its dot.
struct CodePreserver {
    private struct Span {
        let placeholder: String
        let literal: String
    }

    private var spans: [Span] = []

    mutating func mask(_ text: String) -> String {
        let patterns = [
            "`[^`\\n]+`",
            "(?<![\\p{L}\\p{N}_.])\\d+\\.\\d+(?:[kKmMbBtT])?(?![\\p{L}\\p{N}_.])",
            "(?<![\\p{L}\\p{N}_.-])(?:\\.{1,2}/)?(?:[\\p{L}\\p{N}_.-]+/)+[\\p{L}\\p{N}_-](?:[\\p{L}\\p{N}_.-]*[\\p{L}\\p{N}_-])?",
            "(?<![\\p{L}\\p{N}_.-])[\\p{L}\\p{N}_-]+\\.(?:swift|ts|tsx|js|jsx|mjs|cjs|py|rs|go|java|kt|kts|json|ya?ml|toml|ini|cfg|env|conf|md|txt|sh|bash|zsh|css|scss|html|sql|xml|csv|lock|plist|png|jpe?g|gif|svg|pdf|ico|webp|log|diff|patch)(?![\\p{L}\\p{N}_.-])",
        ]
        var ranges: [NSRange] = []
        let source = text as NSString
        let full = NSRange(location: 0, length: source.length)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            ranges.append(contentsOf: regex.matches(in: text, range: full).map(\.range))
        }
        ranges.sort { lhs, rhs in
            lhs.location == rhs.location ? lhs.length > rhs.length : lhs.location < rhs.location
        }

        var accepted: [NSRange] = []
        for range in ranges where !accepted.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
            accepted.append(range)
        }

        let output = NSMutableString(string: text)
        for range in accepted.reversed() {
            let literal = source.substring(with: range)
            let placeholder = "\u{E000}\(spans.count)\u{E001}"
            spans.append(Span(placeholder: placeholder, literal: literal))
            output.replaceCharacters(in: range, with: placeholder)
        }
        return output as String
    }

    func restore(_ text: String) -> String {
        var output = text
        for span in spans {
            output = output.replacingOccurrences(of: span.placeholder, with: span.literal)
        }
        return output
    }
}

/// Splits a document into prose and fenced code. Fences are kept verbatim and
/// never handed to the formatter; an unclosed fence is treated as code too, so
/// a truncated dictation can never have its code reinterpreted as prose.
enum FencedBlocks {
    enum Segment: Equatable {
        case prose(String)
        case code(String)
    }

    static func split(_ text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        var segments: [Segment] = []
        var prose: [String] = []
        var code: [String] = []
        var open: (character: Character, count: Int)?

        func flushProse() {
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.prose(joined))
            }
            prose.removeAll(keepingCapacity: true)
        }

        for line in text.components(separatedBy: "\n") {
            if let fence = open {
                code.append(line)
                if isClosing(line, fence: fence) {
                    segments.append(.code(code.joined(separator: "\n")))
                    code.removeAll(keepingCapacity: true)
                    open = nil
                }
                continue
            }
            if let fence = openingFence(line) {
                flushProse()
                open = fence
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if !code.isEmpty {
            segments.append(.code(code.joined(separator: "\n")))
        }
        flushProse()
        return segments
    }

    private static func openingFence(_ line: String) -> (character: Character, count: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        return (first, count)
    }

    private static func isClosing(_ line: String, fence: (character: Character, count: Int)) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let count = trimmed.prefix { $0 == fence.character }.count
        guard count >= fence.count else { return false }
        return trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }
}
