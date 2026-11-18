import Foundation
import SuperflowKernel

struct PlainShortcutRecord: Sendable, Equatable {
    var trigger: String
    var content: String
    var match: ShortcutMatch
}

struct PlainShortcutParseResult: Sendable {
    var records: [PlainShortcutRecord]
    var malformed: Int
}

/// Stable, human-editable plain-text format:
///
///   # comment
///   trigger => wholeUtterance | content (newlines escaped as \n)
///
/// The match kind is a closed enum, so it is written unescaped between the two
/// delimiters; all user text is escaped by the shared codec and round-trips.
enum ShortcutPlainText {
    static func encode(_ entries: [ShortcutEntry]) -> String {
        let ordered = entries.sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled { return lhs.enabled }
            let trigger = lhs.trigger.localizedCaseInsensitiveCompare(rhs.trigger)
            if trigger != .orderedSame { return trigger == .orderedAscending }
            return lhs.id < rhs.id
        }
        var lines = ["# Superflow Shortcuts (plain text)"]
        for entry in ordered {
            lines.append("""
            \(KnowledgePlainTextCodec.escape(entry.trigger)) => \(entry.match.rawValue) | \
            \(KnowledgePlainTextCodec.escape(entry.content))
            """)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func decode(_ text: String) -> PlainShortcutParseResult {
        var records: [PlainShortcutRecord] = []
        var malformed = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let first = KnowledgePlainTextCodec.firstUnescaped("=>", in: line) else {
                malformed += 1
                continue
            }
            let afterArrow = String(line[first.upperBound...])
            guard let pipe = KnowledgePlainTextCodec.firstUnescaped("|", in: afterArrow) else {
                malformed += 1
                continue
            }
            let trigger = KnowledgePlainTextCodec.unescape(
                String(line[..<first.lowerBound]).trimmingCharacters(in: .whitespaces))
            let matchRaw = String(afterArrow[..<pipe.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard let match = ShortcutMatch(rawValue: matchRaw) else {
                malformed += 1
                continue
            }
            let content = KnowledgePlainTextCodec.unescape(
                String(afterArrow[pipe.upperBound...]).trimmingCharacters(in: .whitespaces))
            guard !trigger.isEmpty, !content.isEmpty else {
                malformed += 1
                continue
            }
            records.append(PlainShortcutRecord(trigger: trigger, content: content, match: match))
        }
        return PlainShortcutParseResult(records: records, malformed: malformed)
    }
}
