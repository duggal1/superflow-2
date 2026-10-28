import Foundation
import SuperflowKernel
import SuperflowPorts

public struct NumberCleanupStage: TextStage {
    public let id = "numbers"
    private let grouping: NumberOptions.Grouping

    public init(grouping: NumberOptions.Grouping = .western) { self.grouping = grouping }

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var options = NumberOptions()
        options.small = context.settings.spellOutSmallNumbers ? .words : .digits
        options.grouping = grouping
        options.largeNumberStyle = context.settings.numberStyle
        var output = draft
        var literals = Set<String>()
        output.text = draft.text.components(separatedBy: "\n").map { line in
            let words = TextNumbers.apply(Tokenizer.words(line, protected: draft.protected), options)
            for word in words where word.protected { literals.insert(word.core) }
            return Tokenizer.join(words)
        }.joined(separator: "\n")
        output.protected.literals.formUnion(literals)
        return output
    }
}
