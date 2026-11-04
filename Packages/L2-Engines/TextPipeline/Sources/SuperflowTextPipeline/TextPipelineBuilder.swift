import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCleanup
import SuperflowTextCodeAware
import SuperflowTextCodeSpeak
import SuperflowTextCommands
import SuperflowTextGrammarGate
import SuperflowTextLexicon
import SuperflowTextLineFormat
import SuperflowTextNumbers
import SuperflowTextShortcuts
import SuperflowTechDictionary

public struct TextPipelineDependencies: Sendable {
    public var lexiconEntries: [LexiconEntry]
    public var shortcuts: [ShortcutEntry]
    public var cleaner: CleanupService?
    public var grammarChecker: (any GrammarChecker)?
    public var grammarPolicy: GrammarGatePolicy
    /// The explicitly injected project scope. Nil means filename-only cleanup:
    /// no path is resolved and no directory is walked.
    public var project: ProjectContext?

    public init(lexiconEntries: [LexiconEntry] = [], shortcuts: [ShortcutEntry] = [],
                cleaner: CleanupService? = nil, grammarChecker: (any GrammarChecker)? = nil,
                grammarPolicy: GrammarGatePolicy = .loadBundled(),
                project: ProjectContext? = nil) {
        self.lexiconEntries = lexiconEntries
        self.shortcuts = shortcuts
        self.cleaner = cleaner
        self.grammarChecker = grammarChecker
        self.grammarPolicy = grammarPolicy
        self.project = project
    }
}

/// S1-mini receives the raw transcript before deterministic text formatting.
public enum TextPipelineBuilder {
    public static func make(settings: AppSettings,
                            dependencies: TextPipelineDependencies = TextPipelineDependencies()) -> TextPipeline {
        var stages: [any SuperflowPorts.TextStage] = []
        if settings.cleanupEnabled, let cleaner = dependencies.cleaner {
            stages.append(CleanupStage(service: cleaner))
        }
        stages.append(PostDedupeStage())
        stages.append(FormattingStage())
        if settings.commandsEnabled {
            stages.append(CommandsStage())
        }
        if !dependencies.shortcuts.isEmpty {
            stages.append(ShortcutsStage(entries: dependencies.shortcuts))
        }
        stages.append(SpokenCodeStage())
        stages.append(CodingLanguageStage())
        stages.append(NumbersAdapter())
        if settings.codeSpeakEnabled {
            stages.append(CodeSpeakStage())
        }
        stages.append(LexiconStage(entries: dependencies.lexiconEntries, id: "lexicon"))
        if settings.codeAware.enabled {
            stages.append(CodeAwareStage(settings: settings.codeAware,
                                         project: dependencies.project))
        }
        stages.append(LineFormatStage(settings: settings.lineFormat))
        stages.append(NormalizeAdapter())
        stages.append(ModelNameStage())
        // Final deterministic layer. The dictionary is loaded once and is never
        // exposed to ASR or the cleanup model. Tier B aliases are context-gated.
        let gate = TechDictionaryGate(userEntries: dependencies.lexiconEntries,
                                      project: dependencies.project)
        stages.append(LexiconStage(entries: TechDictionary.lexiconEntries(),
                                   id: "techDictionary",
                                   includeCanonical: false,
                                   filter: { trigger, canonical, line, context in
                                       gate.accepts(trigger: trigger, canonical: canonical,
                                                    line: line, context: context)
                                   }))

        let seed = Set(dependencies.lexiconEntries.filter(\.enabled).map(\.canonical).filter { !$0.isEmpty })
        let tokenCounter: (@Sendable (String) async -> Int)?
        if let cleaner = dependencies.cleaner {
            tokenCounter = { text in await cleaner.countTokens(text) }
        } else {
            tokenCounter = nil
        }
        return TextPipeline(stages: stages, seedProtected: seed, tokenCounter: tokenCounter)
    }
}
