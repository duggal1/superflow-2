import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextNumbers
import SuperflowTextLineFormat

struct NumbersAdapter: SuperflowPorts.TextStage {
    let id = "numbers"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var config = TextNumbersConfig()
        config.smallNumberThreshold = context.settings.spellOutSmallNumbers ? 10 : 0
        config.currencyStyle = context.settings.numberStyle == .full ? .full : .abbreviated
        var result = await NumberCleanupStage().apply(draft, context: context)
        var converted = Set<String>()
        result.text = result.text.components(separatedBy: "\n").map { line in
            let slices = line.split(whereSeparator: \.isWhitespace)
            let explicit = draft.protected.ranges(in: line, detect: false)
            var words = Tokenizer.words(line, protected: draft.protected)
            for index in words.indices {
                let range = slices[index].startIndex..<slices[index].endIndex
                let isExplicit = explicit.contains { $0.overlaps(range) }
                let core = words[index].core
                let numeric = core.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
                    && core.contains(where: \.isNumber)
                let compact = index > 0 && words[index - 1].key == "half" && core == "1M"
                if !isExplicit && (numeric || compact) { words[index].isProtected = false }
                words[index].glue = false
            }
            let output = TextNumbersStage(config: config).apply(TextDraft(words: words))
            converted.formUnion(output.words.filter(\.isProtected).map(\.literal).filter { !$0.isEmpty })
            return output.text
        }.joined(separator: "\n")
        result.protected.literals.formUnion(converted)
        return result
    }
}

struct NormalizeAdapter: SuperflowPorts.TextStage {
    let id = "normalize"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit else { return draft }
        var output = draft
        output.text = Normalizer.normalize(draft.text)
        return output
    }
}
