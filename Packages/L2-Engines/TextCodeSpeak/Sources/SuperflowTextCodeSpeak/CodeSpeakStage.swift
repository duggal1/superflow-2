import SuperflowKernel
import SuperflowPorts

/// Turns dictated code spelling into literals: identifiers, paths, flags,
/// bounded symbols and backtick/code-block wrappers.
///
/// Safe by construction: protected spans are skipped, every rule is bounded to
/// one clause, and an ambiguous command is left as ordinary prose.
public struct CodeSpeakStage: ExplainingTextStage {
    public let id: String

    public init(id: String = "codeSpeak") {
        self.id = id
    }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        let output = CodeSpeakRewriter.rewrite(draft.text, protected: draft.protected, stageID: id)
        var next = draft
        next.text = output.text
        next.protected.literals.formUnion(output.protected)
        return next
    }

    public func explainEdits(before: TranscriptDraft, after: TranscriptDraft,
                             context: TextContext) async -> [TextEdit]? {
        let output = CodeSpeakRewriter.rewrite(before.text, protected: before.protected, stageID: id)
        guard output.text == after.text else { return nil }
        return output.edits.isEmpty ? nil : output.edits
    }
}
