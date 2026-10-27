import Foundation
import SuperflowKernel

/// Word-level diff used by the pipeline's explain mode. Deterministic and
/// allocation-bounded: above `maxTokens` a single coarse span is returned
/// instead of an O(n*m) alignment.
enum TextWordDiff {
    static let maxTokens = 800

    private struct Token {
        let range: Range<String.Index>
        let text: String
    }

    private enum Op {
        case equal(Int, Int)
        case delete(Int)
        case insert(Int)
    }

    static func edits(stageID: String, before: String, after: String) -> [TextEdit] {
        guard before != after else { return [] }
        let lhs = tokens(in: before)
        let rhs = tokens(in: after)
        if lhs.isEmpty && rhs.isEmpty { return [] }
        guard lhs.count <= maxTokens, rhs.count <= maxTokens else {
            return [coarse(stageID: stageID, before: before, after: after)]
        }
        let ops = alignment(lhs, rhs)
        return grouped(stageID: stageID, before: before, after: after, lhs: lhs, rhs: rhs, ops: ops)
    }

    /// Tokens cover the whole string: each word plus the separator before it.
    /// No character is dropped, so spans can be sliced directly.
    private static func tokens(in text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        var out: [Token] = []
        var cursor = text.startIndex
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords]) { _, range, _, _ in
            if cursor < range.lowerBound {
                out.append(Token(range: cursor..<range.lowerBound,
                                 text: String(text[cursor..<range.lowerBound])))
            }
            out.append(Token(range: range, text: String(text[range])))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            out.append(Token(range: cursor..<text.endIndex, text: String(text[cursor..<text.endIndex])))
        }
        return out
    }

    private static func alignment(_ lhs: [Token], _ rhs: [Token]) -> [Op] {
        let n = lhs.count
        let m = rhs.count
        var table = [[UInt16]](repeating: [UInt16](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    if lhs[i - 1].text == rhs[j - 1].text {
                        table[i][j] = table[i - 1][j - 1] + 1
                    } else {
                        table[i][j] = max(table[i - 1][j], table[i][j - 1])
                    }
                }
            }
        }

        var reversed: [Op] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, lhs[i - 1].text == rhs[j - 1].text {
                reversed.append(.equal(i - 1, j - 1))
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || table[i][j - 1] >= table[i - 1][j] {
                reversed.append(.insert(j - 1))
                j -= 1
            } else {
                reversed.append(.delete(i - 1))
                i -= 1
            }
        }
        return reversed.reversed()
    }

    private static func grouped(stageID: String, before: String, after: String,
                                lhs: [Token], rhs: [Token], ops: [Op]) -> [TextEdit] {
        var edits: [TextEdit] = []
        var lastBeforeEnd = 0
        var lastAfterEnd = 0
        var index = 0

        while index < ops.count {
            switch ops[index] {
            case let .equal(i, j):
                lastBeforeEnd = offset(lhs[i].range.upperBound, in: before)
                lastAfterEnd = offset(rhs[j].range.upperBound, in: after)
                index += 1

            case .delete, .insert:
                var removed: [Int] = []
                var added: [Int] = []
                while index < ops.count, !isEqual(ops[index]) {
                    switch ops[index] {
                    case let .delete(i): removed.append(i)
                    case let .insert(j): added.append(j)
                    case .equal: break
                    }
                    index += 1
                }

                let input: TextSpan
                if let first = removed.first, let last = removed.last {
                    let start = offset(lhs[first].range.lowerBound, in: before)
                    let end = offset(lhs[last].range.upperBound, in: before)
                    input = TextSpan(location: start, length: end - start)
                } else {
                    input = TextSpan(location: lastBeforeEnd, length: 0)
                }

                let output: TextSpan
                if let first = added.first, let last = added.last {
                    let start = offset(rhs[first].range.lowerBound, in: after)
                    let end = offset(rhs[last].range.upperBound, in: after)
                    output = TextSpan(location: start, length: end - start)
                } else {
                    output = TextSpan(location: lastAfterEnd, length: 0)
                }

                let kind: TextEditKind = removed.isEmpty ? .insert : (added.isEmpty ? .delete : .replace)
                edits.append(TextEdit(stageID: stageID, kind: kind, input: input, output: output))

                if let last = removed.last {
                    lastBeforeEnd = offset(lhs[last].range.upperBound, in: before)
                }
                if let last = added.last {
                    lastAfterEnd = offset(rhs[last].range.upperBound, in: after)
                }
            }
        }
        return edits
    }

    private static func isEqual(_ op: Op) -> Bool {
        if case .equal = op { return true }
        return false
    }

    private static func offset(_ index: String.Index, in text: String) -> Int {
        text[..<index].utf16.count
    }

    private static func coarse(stageID: String, before: String, after: String) -> TextEdit {
        let kind: TextEditKind = before.isEmpty ? .insert : (after.isEmpty ? .delete : .replace)
        return TextEdit(stageID: stageID, kind: kind,
                        input: TextSpan(location: 0, length: before.utf16.count),
                        output: TextSpan(location: 0, length: after.utf16.count))
    }
}
