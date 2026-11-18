import Foundation
import SuperflowKernel

struct PlainLexiconRecord: Sendable, Equatable {
    var triggers: [String]
    var canonical: String
}

struct PlainLexiconParseResult: Sendable {
    var records: [PlainLexiconRecord]
    /// Non-comment, non-blank lines that could not be parsed. Reported as
    /// skipped so an import never silently drops user data.
    var malformed: Int
}

/// Stable, human-editable plain-text format:
///
///   # comment
///   trigger one, trigger two => canonical form
///
/// Delimiters and newlines inside values are backslash-escaped by the shared
/// codec, so unicode, quotes, commas and `=>` all round-trip losslessly.
enum LexiconPlainText {
    static func encode(_ entries: [LexiconEntry]) -> String {
        let ordered = entries.sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled { return lhs.enabled }
            let name = lhs.canonical.localizedCaseInsensitiveCompare(rhs.canonical)
            if name != .orderedSame { return name == .orderedAscending }
            return lhs.id < rhs.id
        }
        var lines = ["# Superflow Dictionary (plain text)"]
        for entry in ordered {
            let triggers = entry.triggers.map(KnowledgePlainTextCodec.escape)
                .joined(separator: ", ")
            lines.append("\(triggers) => \(KnowledgePlainTextCodec.escape(entry.canonical))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func decode(_ text: String) -> PlainLexiconParseResult {
        var records: [PlainLexiconRecord] = []
        var malformed = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let delimiter = KnowledgePlainTextCodec.firstUnescaped("=>", in: line) else {
                malformed += 1
                continue // malformed line: skip, do not import a half-entry
            }
            let left = String(line[..<delimiter.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(line[delimiter.upperBound...]).trimmingCharacters(in: .whitespaces)
            let triggers = KnowledgePlainTextCodec.splitUnescaped(left, by: ",")
                .map { KnowledgePlainTextCodec.unescape($0.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
            let canonical = KnowledgePlainTextCodec.unescape(right)
            guard !triggers.isEmpty, !canonical.isEmpty else {
                malformed += 1
                continue
            }
            records.append(PlainLexiconRecord(triggers: triggers, canonical: canonical))
        }
        return PlainLexiconParseResult(records: records, malformed: malformed)
    }
}
