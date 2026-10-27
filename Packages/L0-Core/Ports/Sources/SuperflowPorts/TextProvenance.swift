import SuperflowKernel

/// A stage that can attribute its changes to individual rules. Stages that do
/// not conform (or return nil) fall back to the pipeline's word-level diff
/// attributed to the stage id.
public protocol ExplainingTextStage: TextStage {
    func explainEdits(before: TranscriptDraft, after: TranscriptDraft,
                      context: TextContext) async -> [TextEdit]?
}
