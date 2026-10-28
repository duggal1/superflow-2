import Foundation

/// Pure value+range replacement used by the Accessibility fallback when a text
/// view rejects `AXSelectedText` but accepts a whole-value write.
public enum AXValueReplacement {
    /// Replaces the clamped range in `value` with `text`. A nil range appends.
    public static func replacing(value: String, range: (location: Int, length: Int)?,
                                 with text: String) -> String {
        let ns = value as NSString
        guard let range else { return ns.appending(text) }
        let start = max(0, min(range.location, ns.length))
        let end = max(start, min(range.location + range.length, ns.length))
        return ns.replacingCharacters(in: NSRange(location: start, length: end - start), with: text)
    }
}
