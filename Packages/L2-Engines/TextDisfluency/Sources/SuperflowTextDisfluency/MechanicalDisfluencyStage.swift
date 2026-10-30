import Foundation
import SuperflowKernel
import SuperflowPorts

public struct MechanicalDisfluencyStage: TextStage {
    public let id: String
    private let settings: DisfluencySettings

    public init(settings: DisfluencySettings = .init(), id: String = "disfluency") {
        self.settings = settings
        self.id = id
    }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard settings.enabled, !draft.shortCircuit else { return draft }
        var options = DisfluencyOptions()
        options.removeFillers = settings.fillerPrepass
        options.allowedFillers = ["um", "uh", "uhm", "er"]
        options.collapseDuplicates = settings.collapseDuplicates
        options.collapseRepeatedPhrases = settings.collapseRepeatedPhrases
        options.keepDoubles = []
        let lines = draft.text.components(separatedBy: "\n")
        let output = lines.map { line in
            let words = Tokenizer.words(line, protected: draft.protected)
            for word in words {
                options.thresholds[word.key] = max(2, settings.tierAThreshold)
            }
            let cleaned = TextDisfluency.apply(words, options)
            return cleaned == words ? line : Tokenizer.join(cleaned)
        }.joined(separator: "\n")
        var next = draft
        next.text = output
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.text = ""
            next.cleanupState = .cleaned
        }
        return next
    }
}
