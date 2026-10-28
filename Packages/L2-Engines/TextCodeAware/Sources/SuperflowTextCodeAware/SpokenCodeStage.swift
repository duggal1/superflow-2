import SuperflowKernel
import SuperflowPorts

public struct SpokenCodeStage: ExplainingTextStage {
    public let id = "spokenCode"
    public init() {}

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        let result = SpokenCodeRewriter.rewrite(draft.text, protected: draft.protected, stageID: id)
        var output = draft
        output.text = result.text
        output.protected.literals.formUnion(result.protected)
        return output
    }

    public func explainEdits(before: TranscriptDraft, after: TranscriptDraft,
                             context: TextContext) async -> [TextEdit]? {
        let result = SpokenCodeRewriter.rewrite(before.text, protected: before.protected, stageID: id)
        return result.text == after.text ? result.edits : nil
    }
}
