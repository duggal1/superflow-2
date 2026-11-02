import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextDisfluency
import SuperflowTextNumbers

/// Bridges the synchronous word stages to the app's protected transcript pipeline.
struct DisfluencyAdapter: SuperflowPorts.TextStage {
    let id = "disfluency"
    let settings: DisfluencySettings

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit, settings.enabled else { return draft }
        var config = TextDisfluencyStage.Config()
        config.minRun = max(2, settings.tierAThreshold)
        config.maxPhraseLength = settings.collapseRepeatedPhrases ? 8 : 1
        config.stripFillers = settings.fillerPrepass
        config.singleWordAllowlist = Set("first second third fourth fifth i it we you they he she was were my your our the a an to of in on at for with and or but if because what how why when where".split(separator: " ").map(String.init))
        config.legitimatePairs = ["had", "that"]
        guard settings.collapseDuplicates else {
            return await MechanicalDisfluencyStage(settings: settings).apply(draft, context: context)
        }
        let preserved = Set("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty seventy eighty ninety hundred thousand million billion not no never none nothing nobody neither nor cannot without".split(separator: " ").map(String.init))
        var result = draft
        result.text = draft.text.components(separatedBy: "\n").map { line in
            var words = WordTimingProjection.apply(to: Tokenizer.words(line, protected: draft.protected),
                                                   timings: context.wordTimings)
            for index in words.indices where index > 0 && words[index - 1].pause {
                words[index].pauseBefore = .milliseconds(601)
            }
            words = words.map { word in
                var word = word
                if preserved.contains(word.key) || word.key.hasSuffix("n't") { word.isProtected = true }
                word.glue = false
                return word
            }
            return TextDisfluencyStage(config: config).apply(TextDraft(words: words)).text
        }.joined(separator: "\n")
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.cleanupState = .cleaned
        }
        return result
    }
}

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
