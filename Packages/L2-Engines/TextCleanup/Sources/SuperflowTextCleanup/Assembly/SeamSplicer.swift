import Foundation
import SuperflowKernel

public enum SeamSplicer {
    public struct Splice: Sendable {
        public var kept: String
        public var rest: String
        public var aligned: Bool
    }
    private static func norm(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || "$€£₹¥%@_/".contains($0) }
    }
    public static func splice(_ left: String, _ right: String, overlapWords: Int) -> Splice {
        let lhs = Tokenizer.tokens(in: left), rhs = Tokenizer.tokens(in: right)
        let window = min(256, max(12, overlapWords * 2 + 8))
        let start = max(0, lhs.count - window), count = min(window, rhs.count)
        var previous = [Int](repeating: 0, count: count + 1)
        var best = (length: 0, left: 0, right: 0)
        for a in start..<lhs.count {
            var current = [Int](repeating: 0, count: count + 1)
            for b in 0..<count where !norm(lhs[a].core).isEmpty && norm(lhs[a].core) == norm(rhs[b].core) {
                current[b + 1] = previous[b] + 1
                if current[b + 1] > best.length {
                    best = (current[b + 1], a - current[b + 1] + 1, b - current[b + 1] + 1)
                }
            }
            previous = current
        }
        guard best.length >= min(4, max(2, overlapWords / 3)) else {
            return Splice(kept: left, rest: right, aligned: false)
        }
        let midpoint = (1...best.length).first {
            lhs[best.left + $0 - 1].trail.contains { ".?!".contains($0) }
        } ?? max(1, best.length / 2)
        let cut = lhs[best.left + midpoint - 1].range.upperBound
        let next = best.right + midpoint
        return Splice(kept: String(left[..<cut]),
                      rest: next < rhs.count ? String(right[rhs[next].range.lowerBound...]) : "", aligned: true)
    }

    public static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
