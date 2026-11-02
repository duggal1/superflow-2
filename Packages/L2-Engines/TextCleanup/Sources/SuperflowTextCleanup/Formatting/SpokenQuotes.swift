import Foundation

public enum SpokenQuotes {
    public enum Style: Sendable, Equatable { case straight, curly }

    private static let openers: [[String]] = [["open", "quote"], ["begin", "quote"], ["quote"]]
    private static let closers: [[String]] = [
        ["end", "of", "quote"], ["close", "quote"], ["end", "quote"], ["unquote"],
    ]

    public static func apply(_ text: String, style: Style = .straight) -> String {
        text.components(separatedBy: "\n")
            .map { apply(line: $0, style: style) }
            .joined(separator: "\n")
    }

    private static func apply(line: String, style: Style) -> String {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let (openQuote, closeQuote) = style == .straight ? ("\"", "\"") : ("“", "”")
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            guard let openLength = match(openers, at: index, in: tokens) else {
                output.append(tokens[index])
                index += 1
                continue
            }
            let from = index + openLength
            var closer: (at: Int, length: Int)?
            var search = from
            while search < tokens.count, search - from <= 60 {
                if let length = match(closers, at: search, in: tokens) {
                    closer = (search, length)
                    break
                }
                search += 1
            }
            // Noun use ("a quote from Lincoln") has no closer and stays untouched.
            guard let closer, closer.at > from else {
                output.append(tokens[index])
                index += 1
                continue
            }
            var inner = Array(tokens[from..<closer.at])
            let trailing = trailingPunctuation(of: tokens[closer.at + closer.length - 1])
            inner[0] = openQuote + inner[0]
            inner[inner.count - 1] += closeQuote + trailing
            output.append(contentsOf: inner)
            index = closer.at + closer.length
        }
        return output.joined(separator: " ")
    }

    private static func match(_ patterns: [[String]], at index: Int, in tokens: [String]) -> Int? {
        for pattern in patterns.sorted(by: { $0.count > $1.count }) where index + pattern.count <= tokens.count {
            let matches = pattern.indices.allSatisfy {
                tokens[index + $0].lowercased().filter(\.isLetter) == pattern[$0]
            }
            if matches { return pattern.count }
        }
        return nil
    }

    private static func trailingPunctuation(of word: String) -> String {
        String(word.reversed().prefix(while: { ".,;:!?".contains($0) }).reversed())
    }
}

/// S1-mini must keep every quote mark the rewritten input had.
public enum QuoteGate {
    public static func count(_ s: String) -> Int {
        s.filter { "\"“”".contains($0) }.count
    }

    public static func preserved(input: String, output: String) -> Bool {
        count(input) == count(output)
    }
}
