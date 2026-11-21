import Foundation
import SuperflowKernel
import SuperflowPorts

struct DictatedLayoutStage: SuperflowPorts.TextStage {
    let id = "dictatedLayout"

    private static let dashList = #"(?i)^(?:heading[ \t]+)?([^\n.!?]*\b(?:checklist|list)\b(?:[ \t]+for[ \t]+[^\n.!?]+?)?)[ \t]*(?:new line[ \t]+|:[ \t]*)?(?=dash\b)"#
    private static let dash = #"(?i)(?<!\S)dash[ \t]+(?=\p{L})"#
    private static let paragraph = #"(?i)^(?:first paragraph)[ \t]+(.+?)[ \t]+new paragraph[ \t]+(?=(?:i|we|you|he|she|it|they|the)\b)"#

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit, !draft.text.contains("```"), !draft.text.contains("~~~") else { return draft }
        let input = draft.text
        var output = draft
        if let heading = input.range(of: Self.dashList, options: .regularExpression) {
            let rest = input[heading.upperBound...]
            let body = rest.replacingOccurrences(of: Self.dash, with: "\n- ", options: .regularExpression)
            if body.split(separator: "\n").count >= 3 {
                let title = input[heading].replacingOccurrences(
                    of: #"(?i)^heading\s+|\s+new line\s*$|[: \t]+$"#,
                    with: "", options: .regularExpression)
                output.text = title + ":" + body
                return output
            }
        }
        output.text = input.replacingOccurrences(of: Self.paragraph, with: "$1\n\n", options: .regularExpression)
        return output
    }
}
