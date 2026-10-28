import SuperflowKernel
import SuperflowPorts

/// Removes mechanical disfluency before the model or any other stage runs.
public struct DisfluencyStage: ExplainingTextStage {
    public let id: String
    private let settings: DisfluencySettings

    public init(settings: DisfluencySettings = DisfluencySettings(), id: String = "disfluency") {
        self.id = id
        self.settings = settings
    }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        let output = DisfluencyRewriter.rewrite(draft.text, protected: draft.protected,
                                                settings: settings, stageID: id)
        var next = draft
        next.text = output.text
        return next
    }

    public func explainEdits(before: TranscriptDraft, after: TranscriptDraft,
                             context: TextContext) async -> [TextEdit]? {
        let output = DisfluencyRewriter.rewrite(before.text, protected: before.protected,
                                                settings: settings, stageID: id)
        guard output.text == after.text else { return nil }
        return output.edits.isEmpty ? nil : output.edits
    }
}
