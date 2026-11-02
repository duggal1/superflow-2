import Foundation

/// Normalizes list output; it never invents a list from spoken prose.
public enum ListShaper {
    public enum NumberStyle: Sendable, Equatable { case dot, paren }

    public struct Options: Sendable, Equatable {
        public var bullet: String
        public var numberStyle: NumberStyle
        public init(bullet: String = "-", numberStyle: NumberStyle = .dot) {
            self.bullet = bullet
            self.numberStyle = numberStyle
        }
    }

    public static func apply(_ text: String, options: Options = Options()) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            lines.append(contentsOf: splitInline(line))
        }
        return normalize(lines, options).joined(separator: "\n")
    }

    // MARK: inline run to lines

    private static let inlineMarker = #"(?<![\w.])(\d{1,2})[.)]\s+(?=\S)"#

    public static func splitInline(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: inlineMarker) else { return [line] }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 3 else { return [line] }
        let numbers = matches.compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        guard numbers == Array(1...matches.count) else { return [line] }

        var output: [String] = []
        let intro = ns.substring(to: matches[0].range.location)
            .trimmingCharacters(in: .whitespaces)
        if !intro.isEmpty { output.append(intro) }
        for (index, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let item = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespaces)
            output.append("\(numbers[index]). \(item)")
        }
        return output
    }

    // MARK: consistent markers

    private enum Kind { case numbered, bullet, prose }

    private static func parse(_ line: String) -> (kind: Kind, content: String) {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let regex = try? NSRegularExpression(pattern: #"^\s*(\d{1,2})[.)]\s+(.*)$"#),
           let match = regex.firstMatch(in: line, range: full) {
            return (.numbered, ns.substring(with: match.range(at: 2)))
        }
        if let regex = try? NSRegularExpression(pattern: #"^\s*[-•*]\s+(.*)$"#),
           let match = regex.firstMatch(in: line, range: full) {
            return (.bullet, ns.substring(with: match.range(at: 1)))
        }
        return (.prose, line)
    }

    private static func normalize(_ lines: [String], _ options: Options) -> [String] {
        var output: [String] = []
        var index = 0
        while index < lines.count {
            let first = parse(lines[index])
            guard first.kind != .prose else {
                output.append(lines[index])
                index += 1
                continue
            }
            var cursor = index
            var items: [String] = []
            while cursor < lines.count, parse(lines[cursor]).kind == first.kind {
                items.append(parse(lines[cursor]).content)
                cursor += 1
            }
            // A lone marker is not a list and must never be renumbered.
            if items.count < 2 {
                output.append(lines[index])
                index = cursor
                continue
            }
            for (number, item) in items.enumerated() {
                switch first.kind {
                case .numbered:
                    output.append(options.numberStyle == .dot
                        ? "\(number + 1). \(item)" : "\(number + 1)) \(item)")
                case .bullet:
                    output.append("\(options.bullet) \(item)")
                case .prose:
                    break
                }
            }
            index = cursor
        }
        return output
    }
}
