import Foundation

/// Repairs spoken enumeration markers that S1-mini renders as inline hyphens,
/// comma-separated fragments or pseudo-decimals instead of Markdown bullets.
///
/// This is a layout-only repair: it never adds, removes or rewrites a content
/// word. It fires only on a line carrying three or more ordered markers, so
/// ordinary prose containing a dash or the word "point" is left untouched.
/// Fenced code and already-bulleted lines are never processed.
public enum SpokenMarkerListShaper {
    private enum Kind { case hyphen, bullet, decimal, point }

    public static func apply(_ text: String) -> String {
        guard !text.contains("```"), !text.contains("~~~") else { return text }
        var result: [String] = []
        for line in text.components(separatedBy: "\n") {
            result.append(shape(line) ?? line)
        }
        return result.joined(separator: "\n")
    }

    private static func shape(_ line: String) -> String? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []
        var kind: Kind?

        if let re = try? NSRegularExpression(pattern: #"(?<![\w-])-(?=[[:alpha:]])"#) {
            let matches = re.matches(in: line, range: full).map(\.range)
            if matches.count >= 3 { ranges = matches; kind = .hyphen }
        }
        if kind == nil, let re = try? NSRegularExpression(pattern: #"(?i)\bbullet,?\s+"#) {
            let matches = re.matches(in: line, range: full).map(\.range)
            if matches.count >= 3 { ranges = matches; kind = .bullet }
        }
        if kind == nil, let re = try? NSRegularExpression(pattern: #"(?<![\w.])0\.0?([1-9])(?![\d])"#) {
            let matches = re.matches(in: line, range: full).map(\.range)
            if matches.count >= 3 { ranges = matches; kind = .decimal }
        }
        if kind == nil, let re = try? NSRegularExpression(pattern: #"(?i)\bpoint\s+(one|two|three|four|five)(?=\s)"#) {
            let matches = re.matches(in: line, range: full).map(\.range)
            if matches.count >= 3 { ranges = matches; kind = .point }
        }
        guard let kind, (3...10).contains(ranges.count) else { return nil }

        // Numeric/spoken markers must be in ascending order 1, 2, 3 ...
        // Otherwise "0.1" in a technical measurement must stay a measurement.
        if kind == .decimal || kind == .point {
            var expected = 1
            for range in ranges {
                let token = ns.substring(with: range).lowercased()
                let value: Int
                if kind == .decimal {
                    value = Int(token.filter(\.isNumber).last.map(String.init) ?? "0") ?? 0
                } else {
                    let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5]
                    value = words.first(where: { token.hasSuffix($0.key) })?.value ?? 0
                }
                guard value == expected else { return nil }
                expected += 1
            }
        }

        let intro = ns.substring(to: ranges[0].location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard intro.split(whereSeparator: \.isWhitespace).count <= 8 else { return nil }

        // Content before the first marker (with markers removed) must equal the
        // content of the emitted items, word for word. This is the hard guard
        // that makes the shape safe for technical dictation.
        var region = ns.substring(from: ranges[0].location) as NSString
        for range in ranges.reversed() {
            let local = NSRange(location: range.location - ranges[0].location,
                                length: range.length)
            guard local.location >= 0, NSMaxRange(local) <= region.length else { return nil }
            region = region.replacingCharacters(in: local, with: "") as NSString
        }

        var items: [String] = []
        for (index, range) in ranges.enumerated() {
            let start = NSMaxRange(range)
            let end = index + 1 < ranges.count ? ranges[index + 1].location : ns.length
            var item = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Separator commas are part of the broken layout, not content.
            item = item.replacingOccurrences(of: ",", with: " ")
            item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: ".!?;:"))
            item = item.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !item.isEmpty,
                  (1...20).contains(item.split(whereSeparator: \.isWhitespace).count) else { return nil }
            items.append(item)
        }

        guard contentWords(region as String) == contentWords(items.joined(separator: " ")) else { return nil }
        let header = intro.isEmpty ? "" : intro + "\n"
        return header + items.map { "- " + $0 }.joined(separator: "\n")
    }

    private static func contentWords(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init).filter { !$0.isEmpty }
    }
}
