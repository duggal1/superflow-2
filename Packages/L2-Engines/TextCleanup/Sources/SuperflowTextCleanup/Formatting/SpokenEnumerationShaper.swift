import Foundation

/// Structural interpretation of explicitly enumerated speech. This is a
/// fallback for cases where S1-mini did not emit list markers itself. It does
/// not run on prose with ambiguous ordinal words.
public enum SpokenEnumerationShaper {
    private static let ordinals: [String] = [
        "first", "second", "third", "fourth", "fifth", "sixth",
        "seventh", "eighth", "ninth", "tenth",
    ]
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![\w])(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)(?=\s|[:,])"#)

    public static func apply(_ text: String) -> String {
        let fence = String(repeating: "\u{60}", count: 3)
        guard !text.contains(fence), !text.contains("~~~") else { return text }
        return text.components(separatedBy: "\n").map(shapeLine).joined(separator: "\n")
    }

    private static func shapeLine(_ line: String) -> String {
        guard !line.contains("1. ") && !line.contains("1) ") else { return line }
        let ns = line as NSString
        let markers = pattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard markers.count >= 2, markers.count <= 10 else { return line }
        if markers.count == 2, !markers.contains(where: { marker in
            let end = NSMaxRange(marker.range)
            return end < ns.length && [",", ":"].contains(ns.substring(with: NSRange(location: end, length: 1)))
        }) { return line }

        for (index, marker) in markers.enumerated() {
            guard ordinals.firstIndex(of: ns.substring(with: marker.range).lowercased()) == index else {
                return line
            }
        }
        let intro = ns.substring(to: markers[0].range.location).trimmingCharacters(in: .whitespaces)
        // A vague "first ... second ..." mid-sentence is not necessarily a list.
        let introAllowed = intro.isEmpty || intro.hasSuffix(":")
            || (markers.count >= 3 && intro.split(whereSeparator: \.isWhitespace).count <= 6)
        guard introAllowed else { return line }

        var items: [String] = []
        for (index, marker) in markers.enumerated() {
            let start = NSMaxRange(marker.range)
            let end = index + 1 < markers.count ? markers[index + 1].range.location : ns.length
            var item = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if item.first == "," || item.first == ":" {
                item.removeFirst()
                item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard item.split(whereSeparator: \.isWhitespace).count >= 2 else { return line }
            items.append(item)
        }
        let rendered = items.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return (intro.isEmpty ? "" : intro + "\n") + rendered.joined(separator: "\n")
    }
}
