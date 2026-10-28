import Foundation

public struct Diagnostic: Sendable, Equatable {
    public let stage: String
    public let message: String
    public init(stage: String, message: String) {
        self.stage = stage
        self.message = message
    }
}

/// Literal strings (dictionary terms, URLs, code) that no stage may edit.
public struct Protected: Sendable, Equatable {
    public var literals: Set<String>

    public init(literals: Set<String> = []) {
        self.literals = literals
    }

    private static let patternStrings: [String] = [
        #"https?://[^\s]+"#,
        #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
        #"[^\s]*[_/\\`][^\s]*"#,
        #"\b[a-z]+[A-Z][A-Za-z]*\b"#,
        #"\b[A-Za-z]*\d[A-Za-z0-9]*\b"#,
    ]

    public func ranges(in text: String, detect: Bool = true) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        for literal in literals where !literal.isEmpty {
            var from = text.startIndex
            while from < text.endIndex, let r = text.range(of: literal, range: from..<text.endIndex) {
                out.append(r)
                from = r.upperBound
            }
        }
        guard detect else { return out }
        let ns = text as NSString
        for pattern in Self.patternStrings {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let r = Range(m.range, in: text) { out.append(r) }
            }
        }
        return out
    }

    public func overlaps(_ r: Range<String.Index>, in text: String, detect: Bool = true) -> Bool {
        ranges(in: text, detect: detect).contains { $0.overlaps(r) }
    }

    public mutating func protect(_ literal: String) {
        guard !literal.isEmpty else { return }
        literals.insert(literal)
    }
}

public struct TranscriptDraft: Sendable, Equatable {
    public var text: String
    public var protected: Protected
    public var diagnostics: [Diagnostic]
    public var shortCircuit: Bool
    public var cleanupState: CleanupState

    public init(text: String, protected: Protected = Protected(), diagnostics: [Diagnostic] = [],
                shortCircuit: Bool = false, cleanupState: CleanupState = .pending) {
        self.text = text
        self.protected = protected
        self.diagnostics = diagnostics
        self.shortCircuit = shortCircuit
        self.cleanupState = cleanupState
    }
}

public struct TextContext: Sendable {
    public var source: AudioSourceKind
    public var speakerID: String?
    public var interactive: Bool
    public var settings: AppSettings
    /// Session-scoped project scope. Nil means TextCodeAware cannot resolve
    /// paths at all; it still normalizes filenames and extensions.
    public var project: ProjectContext?

    public init(source: AudioSourceKind = .mic, speakerID: String? = nil, interactive: Bool = true,
                settings: AppSettings = .default, project: ProjectContext? = nil) {
        self.source = source
        self.speakerID = speakerID
        self.interactive = interactive
        self.settings = settings
        self.project = project
    }

    /// Cleanup context sent to the model. A coding session upgrades the
    /// general context so path-like speech is treated conservatively.
    public var cleanupContext: String {
        if project?.isCoding == true { return "coding" }
        return settings.cleanupContext
    }
}

public struct Token: Sendable, Hashable {
    public let range: Range<String.Index>
    public let lead: String
    public let core: String
    public let trail: String

    public init(range: Range<String.Index>, lead: String, core: String, trail: String) {
        self.range = range
        self.lead = lead
        self.core = core
        self.trail = trail
    }
    public var full: String { lead + core + trail }
    public var endsClause: Bool { trail.contains { ".,;:!?".contains($0) } }
    public var isNumber: Bool { !core.isEmpty && core.allSatisfy { $0.isNumber || $0 == "." || $0 == "," } }
}

public enum Tokenizer {
    /// Splits a line on whitespace. Leading/trailing punctuation is separated from `core`.
    public static func tokens(in line: String) -> [Token] {
        line.split(whereSeparator: { $0.isWhitespace }).map { sub in
            let chars = Array(sub)
            let leadingSet = CharacterSet.punctuationCharacters.union(.symbols)
            var a = 0, b = chars.count
            while a < b, String(chars[a]).rangeOfCharacter(from: leadingSet) != nil,
                  !"$£€₹#@".contains(chars[a]) {
                a += 1
            }
            while b > a, String(chars[b - 1]).rangeOfCharacter(from: leadingSet) != nil,
                  !"%+#/&*".contains(chars[b - 1]) {
                b -= 1
            }
            return Token(range: sub.startIndex..<sub.endIndex,
                         lead: String(chars[0..<a]),
                         core: String(chars[a..<b]),
                         trail: String(chars[b...]))
        }
    }

    public static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }
}

public enum SentenceSplitter {
    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "vs", "etc", "e.g", "i.e", "inc", "ltd",
        "st", "no", "u.s", "a.m", "p.m", "approx", "dept", "fig", "vol", "co", "corp",
    ]

    /// Splits a paragraph into complete sentences plus an unfinished remainder.
    /// The remainder matters for streaming: "Dr." is only a terminator with following whitespace.
    public static func split(_ s: String) -> (complete: [String], remainder: String) {
        let chars = Array(s)
        let n = chars.count
        var out: [String] = []
        var start = 0
        var i = 0
        while i < n {
            let c = chars[i]
            if c == "." || c == "?" || c == "!" {
                var j = i
                while j + 1 < n, ".?!".contains(chars[j + 1]) { j += 1 }
                var k = j
                while k + 1 < n, "\"')]”’".contains(chars[k + 1]) { k += 1 }
                if k + 1 < n, chars[k + 1].isWhitespace, isBoundary(chars, i, j) {
                    out.append(String(chars[start...k]).trimmingCharacters(in: .whitespaces))
                    start = k + 1
                    while start < n, chars[start].isWhitespace { start += 1 }
                    i = start
                    continue
                }
                i = k + 1
                continue
            }
            i += 1
        }
        let remainder = start < n ? String(chars[start...]).trimmingCharacters(in: .whitespaces) : ""
        return (out, remainder)
    }

    /// True when the text ends with a sentence terminator (ignoring abbreviations).
    public static func endsSentence(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, ".?!".contains(last) else { return false }
        let (complete, remainder) = split(trimmed + " ")
        return !complete.isEmpty && remainder.isEmpty
    }

    private static func isBoundary(_ chars: [Character], _ i: Int, _ j: Int) -> Bool {
        if chars[i] != "." { return true }
        if j - i >= 2 { return false }
        var a = i
        while a > 0, !chars[a - 1].isWhitespace { a -= 1 }
        let tok = String(chars[a..<i]).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'([“‘"))
        if abbreviations.contains(tok) { return false }
        if tok.count == 1, let f = tok.first, f.isLetter, f.isUppercase { return false }
        return true
    }
}

public enum TextCapitalization {
    public static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first, first.isLowercase else { return s }
        return first.uppercased() + s.dropFirst()
    }
    public static func capitalizeSentences(_ s: String) -> String {
        var out = ""
        var atStart = true
        var previous: Character? = nil
        for ch in s {
            if atStart, ch.isLetter {
                out.append(Character(ch.uppercased()))
                atStart = false
                previous = ch
                continue
            }
            out.append(ch)
            if (ch == "." || ch == "?" || ch == "!") && (previous == nil || !previous!.isLetter || true) {
                atStart = true
            } else if ch == "\n" {
                atStart = true
            } else if !ch.isWhitespace && !"\"')]”’".contains(ch) {
                atStart = false
            }
            previous = ch
        }
        return out
    }
}
