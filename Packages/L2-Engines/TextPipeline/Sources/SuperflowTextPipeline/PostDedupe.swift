import Foundation
import SuperflowKernel
import SuperflowPorts

enum PostDedupe {
    private static let intentionalDoubles = Set("very really so that had is are bye ha".split(separator: " ").map(String.init))
    private static let protectedWords = Set("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty ninety hundred thousand million billion not no never none nothing nobody neither nor cannot without".split(separator: " ").map(String.init))

    static func apply(_ text: String, protected: Protected = Protected()) -> String {
        text.components(separatedBy: "\n").map { cleanLine($0, protected: protected) }.joined(separator: "\n")
    }

    private static func cleanLine(_ input: String, protected: Protected) -> String {
        var line = input
        var i = 0
        var tokens = Tokenizer.tokens(in: line)
        while true {
            guard i < tokens.count else { return line }
            let maxLength = min(32, (tokens.count - i) / 2)
            var matched = 0
            if maxLength >= 2 {
                for n in stride(from: maxLength, through: 2, by: -1) {
                    let first = tokens[i..<(i + n)]
                    let second = tokens[(i + n)..<(i + 2 * n)]
                    guard !first.allSatisfy({ $0.core.first?.isUppercase == true }),
                          zip(first, second).allSatisfy({ left, right in
                              safe(left, in: line, protected: protected) && safe(right, in: line, protected: protected)
                                  && left.core.lowercased() == right.core.lowercased()
                                  && left.lead.isEmpty && right.lead.isEmpty
                          }), first.dropLast().allSatisfy({ $0.trail.isEmpty || $0.trail == "," }),
                          let last = first.last, last.trail.isEmpty || last.trail == "," else { continue }
                    matched = n
                    break
                }
            }
            if matched == 0, i + 1 < tokens.count {
                let a = tokens[i], b = tokens[i + 1]
                if !intentionalDoubles.contains(a.core.lowercased()),
                   (a.core.first?.isUppercase != true || a.core == "I"),
                   a.core.lowercased() == b.core.lowercased(),
                   a.lead.isEmpty, b.lead.isEmpty, (a.trail.isEmpty || a.trail == ","),
                   safe(a, in: line, protected: protected), safe(b, in: line, protected: protected) {
                    matched = 1
                }
            }
            if matched > 0 {
                line.removeSubrange(tokens[i].range.lowerBound..<tokens[i + matched].range.lowerBound)
                tokens = Tokenizer.tokens(in: line)
            } else { i += 1 }
        }
    }

    private static func safe(_ token: Token, in line: String, protected: Protected) -> Bool {
        let key = token.core.lowercased().replacingOccurrences(of: "’", with: "'")
        return !key.isEmpty && !protectedWords.contains(key) && !key.hasSuffix("n't")
            && !token.core.contains(where: { $0.isNumber || "/_@\\`#.".contains($0) })
            && !protected.overlaps(token.range, in: line)
    }
}

struct PostDedupeStage: SuperflowPorts.TextStage {
    let id = "dedupe"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        output.text = PostDedupe.apply(draft.text, protected: draft.protected)
        return output
    }
}
