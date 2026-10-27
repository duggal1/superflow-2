import Foundation
import SuperflowKernel

/// A line flattened into a normalized character stream. Every character knows
/// which token produced it, and every token knows its half-open character span.
/// A NUL barrier is inserted at clause boundaries and around URLs, emails and
/// code-like tokens so a trigger can never span them.
struct LexiconStream: Sendable {
    static let barrier: Character = "\u{0}"

    let tokens: [Token]
    let characters: [Character]
    let tokenStart: [Int]
    let tokenEnd: [Int]
    let endToken: [Int]
    let isTokenEnd: [Bool]

    static func build(_ line: String) -> LexiconStream {
        let tokens = Tokenizer.tokens(in: line)
        var characters: [Character] = []
        var tokenStart = [Int](repeating: -1, count: tokens.count)
        var tokenEnd = [Int](repeating: -1, count: tokens.count)
        var endToken: [Int] = []
        var isTokenEnd: [Bool] = []

        func appendBarrier() {
            characters.append(barrier)
            endToken.append(-1)
            isTokenEnd.append(false)
        }

        for (index, token) in tokens.enumerated() {
            let lower = token.core.lowercased()
            if lower == "dot" { continue }
            if token.core.isEmpty || token.core.contains("://") || token.core.contains("@") {
                appendBarrier()
                continue
            }
            let normalized = lower.filter { $0.isLetter || $0.isNumber || $0 == "'" }
            if normalized.isEmpty {
                appendBarrier()
                continue
            }
            tokenStart[index] = characters.count
            for character in normalized {
                characters.append(character)
                endToken.append(-1)
                isTokenEnd.append(false)
            }
            tokenEnd[index] = characters.count
            endToken[characters.count - 1] = index
            isTokenEnd[characters.count - 1] = true
            if token.endsClause { appendBarrier() }
        }

        return LexiconStream(tokens: tokens, characters: characters, tokenStart: tokenStart,
                             tokenEnd: tokenEnd, endToken: endToken, isTokenEnd: isTokenEnd)
    }
}

enum LexiconNormalizer {
    /// Collapse case, spacing, hyphens, dots and the spoken word "dot".
    static func key(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .filter { String($0) != "dot" }
            .flatMap { $0.filter { $0.isLetter || $0.isNumber || $0 == "'" } }
            .reduce(into: "") { $0.append($1) }
    }
}
