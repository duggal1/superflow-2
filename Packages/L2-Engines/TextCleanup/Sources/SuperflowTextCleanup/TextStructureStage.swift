import Foundation
import SuperflowKernel
import SuperflowPorts

/// Formatting also runs when the model is unavailable or rejects a candidate.
/// The planner requires explicit ordered markers or repeated bullet commands.
public struct TextStructureStage: SuperflowPorts.TextStage {
    public let id = "structure"
    public init() {}

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit, !draft.text.contains("```"), !draft.text.contains("~~~") else { return draft }
        var output = draft
        output.text = draft.text.components(separatedBy: "\n").map { line in
            ListPlanner.plan(line, protected: draft.protected).map { segment in
                switch segment {
                case .prose(let text): text
                case .list(let lead, let items):
                    ListRenderer.render(lead: lead, items: items, protected: draft.protected)
                }
            }.joined(separator: "\n\n")
        }.joined(separator: "\n")
        return output
    }
}
