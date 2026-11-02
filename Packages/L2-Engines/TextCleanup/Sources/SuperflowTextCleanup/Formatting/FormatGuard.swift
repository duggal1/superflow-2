import Foundation

/// Structure-only formatting. No stage may change, add or remove a word:
/// only line breaks, list markers, quote marks and blank lines move.
public enum FormatGuard {
    /// Words only. List markers are stripped symmetrically on both sides so a
    /// formatter that moves "1." from mid-line to line start is still equal.
    public static func canonical(_ s: String) -> [String] {
        let noMarkers = s.replacingOccurrences(
            of: #"(?<![\w.])\d{1,2}[.)](?=\s)"#, with: " ", options: .regularExpression)
        return noMarkers
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") })
            .map { $0.replacingOccurrences(of: "’", with: "'") }
    }

    public static func preserves(_ before: String, _ after: String) -> Bool {
        canonical(before) == canonical(after)
    }
}

/// Counters only. Never transcript text.
public struct FormatCounters: Sendable, Equatable {
    public var listReverts = 0
    public var paragraphReverts = 0
    public var whitespaceReverts = 0
    public var listsFormatted = 0
    public var paragraphsSplit = 0
    public init() {}
}
