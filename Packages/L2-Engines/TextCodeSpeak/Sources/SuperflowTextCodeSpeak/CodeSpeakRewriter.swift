import Foundation
import SuperflowKernel
import SuperflowPorts

/// The rewritten text, its per-rule provenance and the literals later stages
/// must leave alone.
public struct CodeSpeakOutput: Sendable, Equatable {
    public var text: String
    public var edits: [TextEdit]
    public var protected: Set<String>

    public init(text: String, edits: [TextEdit], protected: Set<String>) {
        self.text = text
        self.edits = edits
        self.protected = protected
    }
}

/// Deterministic spoken-code rewriter. Every rule is local to one clause, and a
/// command whose target is ambiguous (ordinary prose, protected span, or too
/// many words) is left exactly as dictated.
public enum CodeSpeakRewriter {
    struct Candidate {
        let last: Int
        let body: String
        let ruleID: String
        let protect: String?
        let join: SymbolJoin

        init(last: Int, body: String, ruleID: String, protect: String?, join: SymbolJoin = .none) {
            self.last = last
            self.body = body
            self.ruleID = ruleID
            self.protect = protect
            self.join = join
        }
    }

    public static func rewrite(_ text: String, protected: Protected,
                               stageID: String = "codeSpeak") -> CodeSpeakOutput {
        let lines = text.components(separatedBy: "\n")
        var outputLines: [String] = []
        var edits: [TextEdit] = []
        var produced = Set<String>()
        var inputLineStart = 0
        var outputLineStart = 0
        var inFence = false
        var fenceLines: [String] = []

        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.lowercased()
            var newLine = line

            if inFence {
                if marker == "end code block" {
                    newLine = fenceLine(line, replacement: "```", stageID: stageID,
                                        inputLineStart: inputLineStart,
                                        outputLineStart: outputLineStart, edits: &edits)
                    fenceLines.append(newLine)
                    produced.insert(fenceLines.joined(separator: "\n"))
                    fenceLines.removeAll()
                    inFence = false
                } else {
                    fenceLines.append(line)
                }
            } else if marker == "code block" {
                newLine = fenceLine(line, replacement: "```", stageID: stageID,
                                    inputLineStart: inputLineStart,
                                    outputLineStart: outputLineStart, edits: &edits)
                fenceLines = [newLine]
                inFence = true
            } else {
                let protectedRanges = protected.ranges(in: line, detect: true)
                let result = rewriteLine(line, protectedRanges: protectedRanges, stageID: stageID,
                                         inputLineStart: inputLineStart,
                                         outputLineStart: outputLineStart, produced: &produced)
                newLine = result.line
                edits.append(contentsOf: result.edits)
            }

            outputLines.append(newLine)
            inputLineStart += line.utf16.count + (isLast ? 0 : 1)
            outputLineStart += newLine.utf16.count + (isLast ? 0 : 1)
        }
        if inFence, !fenceLines.isEmpty {
            produced.insert(fenceLines.joined(separator: "\n"))
        }
        return CodeSpeakOutput(text: outputLines.joined(separator: "\n"), edits: edits,
                               protected: produced)
    }

    private static func fenceLine(_ line: String, replacement: String, stageID: String,
                                  inputLineStart: Int, outputLineStart: Int,
                                  edits: inout [TextEdit]) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let markerRange = line.range(of: trimmed) else { return line }
        let leading = line[line.startIndex..<markerRange.lowerBound]
        let trailing = line[markerRange.upperBound...]
        let local = NSRange(markerRange, in: line)
        edits.append(TextEdit(
            stageID: stageID, ruleID: "codeBlock.marker", kind: .replace,
            input: TextSpan(location: inputLineStart + local.location, length: local.length),
            output: TextSpan(location: outputLineStart + leading.utf16.count,
                             length: replacement.utf16.count)))
        return leading + replacement + trailing
    }

    private static func rewriteLine(_ line: String, protectedRanges: [Range<String.Index>],
                                    stageID: String, inputLineStart: Int, outputLineStart: Int,
                                    produced: inout Set<String>) -> (line: String, edits: [TextEdit]) {
        let chunks = CodeSpeakParser.parse(line)
        guard chunks.contains(where: { CodeSpeakParser.isWord($0.core) }) else {
            return (line, [])
        }

        var out = ""
        var cursor = line.startIndex
        var edits: [TextEdit] = []
        var index = 0

        while index < chunks.count {
            let chunk = chunks[index]
            guard chunk.range.lowerBound >= cursor else { index += 1; continue }
            if overlaps(chunk.range, protectedRanges) {
                out += line[cursor..<chunk.range.upperBound]
                cursor = chunk.range.upperBound
                index += 1
                continue
            }
            guard let candidate = candidate(at: index, chunks: chunks) else {
                out += line[cursor..<chunk.range.upperBound]
                cursor = chunk.range.upperBound
                index += 1
                continue
            }

            var start = chunk.range.lowerBound
            var end = chunks[candidate.last].range.upperBound
            if candidate.join == .leading, !chunk.leading.isEmpty,
               chunk.leading.allSatisfy({ $0.isWhitespace }) {
                start = line.index(start, offsetBy: -chunk.leading.count)
            }
            if candidate.join == .trailing, candidate.last + 1 < chunks.count {
                end = chunks[candidate.last + 1].range.lowerBound
            }
            // An open bracket may already have consumed this token's leading
            // whitespace. Clamp instead of rejecting so "open paren close
            // paren" becomes "()".
            if start < cursor { start = cursor }
            let range = start..<end
            guard !overlaps(range, protectedRanges) else {
                out += line[cursor..<chunk.range.upperBound]
                cursor = chunk.range.upperBound
                index += 1
                continue
            }

            let replacement = chunk.prefix + candidate.body + chunks[candidate.last].suffix
            out += line[cursor..<start]
            let outputStart = outputLineStart + out.utf16.count + chunk.prefix.utf16.count
            out += replacement
            let coreEnd = chunks[candidate.last].range.upperBound
            let bodyEnd = line.index(coreEnd, offsetBy: -chunks[candidate.last].suffix.count)
            let local = NSRange(start..<bodyEnd, in: line)
            edits.append(TextEdit(
                stageID: stageID, ruleID: candidate.ruleID, kind: .replace,
                input: TextSpan(location: inputLineStart + local.location, length: local.length),
                output: TextSpan(location: outputStart, length: candidate.body.utf16.count)))
            if let literal = candidate.protect, protectable(literal) {
                produced.insert(literal)
            }
            cursor = end
            index = candidate.last + 1
        }
        out += line[cursor...]
        return (out, edits)
    }

    private static func overlaps(_ range: Range<String.Index>,
                                 _ ranges: [Range<String.Index>]) -> Bool {
        ranges.contains { $0.overlaps(range) }
    }

    /// A single lowercase word is indistinguishable from prose, so only
    /// code-shaped output is protected from later stages.
    private static func protectable(_ literal: String) -> Bool {
        guard literal.count > 1 else { return false }
        if literal.contains(where: { "_./\\-`".contains($0) }) { return true }
        return literal.contains { $0.isUppercase }
    }
}
