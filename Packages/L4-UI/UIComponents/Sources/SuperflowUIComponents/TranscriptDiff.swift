import Foundation

public enum TranscriptDiff {
    public struct Token: Sendable {
        public let text: String
        public let gap: String
        fileprivate let key: String
        public fileprivate(set) var level = 0
    }

    public struct Hunk: Sendable, Equatable {
        public let from: String
        public let to: String
    }

    public struct Result: Sendable {
        public let raw: [Token]
        public let cleaned: [Token]
        public let hunks: [Hunk]
        public let removed: Int
        public let rewritten: Int
        public let polished: Int
        public let ratio: Double
    }

    private static func tokens(_ text: String) -> [Token] {
        var result: [Token] = []
        var word = ""
        var gap = ""
        for character in text {
            if character.isWhitespace {
                gap.append(character)
            } else {
                if !gap.isEmpty {
                    result.append(Token(text: word, gap: gap, key: key(word)))
                    word = ""
                    gap = ""
                }
                word.append(character)
            }
        }
        if !word.isEmpty || !gap.isEmpty {
            result.append(Token(text: word, gap: gap, key: key(word)))
        }
        return result
    }

    private static func key(_ word: String) -> String {
        let normal = word.lowercased().filter { $0.isLetter || $0.isNumber }
        return normal.isEmpty ? word : normal
    }

    public static func compute(raw: String, cleaned: String) -> Result {
        var a = tokens(raw)
        var b = tokens(cleaned)
        let n = a.count, m = b.count
        var hunks: [Hunk] = []
        var removedWords: [String] = []
        var addedWords: [String] = []
        func flush() {
            if !removedWords.isEmpty || !addedWords.isEmpty {
                hunks.append(Hunk(from: removedWords.joined(separator: " "), to: addedWords.joined(separator: " ")))
                removedWords.removeAll()
                addedWords.removeAll()
            }
        }
        if n == 0 || m == 0 || (m > 0 && n <= 4_000_000 / m) {
            let width = m + 1
            var dp = [UInt32](repeating: 0, count: (n + 1) * width)
            if n > 0 && m > 0 {
                for i in stride(from: n - 1, through: 0, by: -1) {
                    for j in stride(from: m - 1, through: 0, by: -1) {
                        dp[i * width + j] = a[i].key == b[j].key
                            ? dp[(i + 1) * width + j + 1] + 1
                            : max(dp[(i + 1) * width + j], dp[i * width + j + 1])
                    }
                }
            }
            var i = 0, j = 0
            while i < n && j < m {
                if a[i].key == b[j].key {
                    flush()
                    if a[i].text != b[j].text { a[i].level = 1; b[j].level = 1 }
                    i += 1; j += 1
                } else if dp[(i + 1) * width + j] >= dp[i * width + j + 1] {
                    a[i].level = 2; removedWords.append(a[i].text); i += 1
                } else {
                    b[j].level = 2; addedWords.append(b[j].text); j += 1
                }
            }
            while i < n { a[i].level = 2; removedWords.append(a[i].text); i += 1 }
            while j < m { b[j].level = 2; addedWords.append(b[j].text); j += 1 }
            flush()
        }
        let removed = a.filter { $0.level == 2 }.count
        let rewritten = b.filter { $0.level == 2 }.count
        let ratio = n == 0 && m == 0 ? 0 : min(1, Double(removed + rewritten) / Double(max(n, m)))
        return Result(raw: a, cleaned: b, hunks: hunks, removed: removed, rewritten: rewritten,
                      polished: b.filter { $0.level == 1 }.count, ratio: ratio)
    }
}
