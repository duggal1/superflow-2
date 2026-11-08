import Foundation
import SuperflowKernel
import SuperflowPorts

public enum ContextKind: Sendable, Equatable { case writing, chat, code, prompting }

public struct FormatConfig: Sendable, Equatable {
    public var lists = true
    public var paragraphs = true
    public var spokenQuotes = false
    public var quoteStyle: SpokenQuotes.Style = .straight
    public var paragraphRules = ParagraphRules()
    public var listOptions = ListShaper.Options()
    public init() {}

    public static func defaults(for kind: ContextKind) -> FormatConfig {
        var config = FormatConfig()
        switch kind {
        case .writing:
            break
        case .chat:
            config.paragraphs = false
        case .code:
            config.paragraphs = false
        case .prompting:
            config.paragraphs = false
        }
        return config
    }

    public static func defaults(for context: TextContext) -> FormatConfig {
        defaults(for: kind(for: context))
    }

    public static func kind(for context: TextContext) -> ContextKind {
        if context.project?.isCoding == true { return .code }
        switch context.settings.cleanupContext.lowercased() {
        case "chat": return .chat
        case "code", "coding": return .code
        case "prompt", "prompting": return .prompting
        default: return .writing
        }
    }
}

/// After S1-mini and PostDedupe. Every step is guarded: a step that would
/// change a word is discarded and counted.
public func shapeOutput(_ cleaned: String, config: FormatConfig,
                        counters: inout FormatCounters) -> String {
    var text = cleaned
    if config.lists, !text.contains("```"), !text.contains("~~~") {
        let spoken = SpokenEnumerationShaper.apply(text)
        if spoken != text {
            text = spoken
            counters.listsFormatted += 1
        }
        let shaped = ListShaper.apply(text, options: config.listOptions)
        if FormatGuard.preserves(text, shaped) {
            if shaped != text { counters.listsFormatted += 1 }
            text = shaped
        } else {
            counters.listReverts += 1
        }
    }
    if config.paragraphs, !text.contains("```"), !text.contains("~~~") {
        let shaped = ParagraphShaper.apply(text, rules: config.paragraphRules)
        if FormatGuard.preserves(text, shaped) {
            if shaped != text { counters.paragraphsSplit += 1 }
            text = shaped
        } else {
            counters.paragraphReverts += 1
        }
    }
    return guardWhitespace(text, Whitespace.tidy(text), counters: &counters)
}

func guardWhitespace(_ input: String, _ output: String, counters: inout FormatCounters) -> String {
    guard FormatGuard.preserves(input, output) else {
        counters.whitespaceReverts += 1
        return input
    }
    return output
}

/// Runs after dedupe and before insertion. Fenced code is never reflowed.
public struct FormattingStage: SuperflowPorts.TextStage {
    public let id = "format"
    public init() {}

    public func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        guard !draft.shortCircuit, !draft.text.isEmpty,
              !draft.text.contains("```"), !draft.text.contains("~~~") else { return draft }
        var output = draft
        var counters = FormatCounters()
        var config = FormatConfig.defaults(for: context)
        // S1-mini owns the Structure axis: under prose the model keeps
        // enumerations inline, and deterministic list shaping must not
        // re-invent bullets the model deliberately withheld.
        let structure = context.settings.cleanupStructure
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if structure == "prose" { config.lists = false }
        output.text = shapeOutput(draft.text, config: config,
                                  counters: &counters)
        if counters.listReverts > 0 {
            output.diagnostics.append(Diagnostic(stage: id,
                message: "list formatting reverted: \(counters.listReverts)"))
        }
        if counters.paragraphReverts > 0 {
            output.diagnostics.append(Diagnostic(stage: id,
                message: "paragraph formatting reverted: \(counters.paragraphReverts)"))
        }
        if counters.whitespaceReverts > 0 {
            output.diagnostics.append(Diagnostic(stage: id,
                message: "whitespace formatting reverted: \(counters.whitespaceReverts)"))
        }
        return output
    }
}
