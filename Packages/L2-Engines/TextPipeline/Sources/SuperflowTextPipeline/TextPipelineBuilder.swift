import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCleanup
import SuperflowTextCodeSpeak
import SuperflowTextCommands
import SuperflowTextGrammarGate
import SuperflowTextLexicon
import SuperflowTextLineFormat
import SuperflowTextNumbers
import SuperflowTextShortcuts

public struct TextPipelineDependencies: Sendable {
    public var lexiconEntries: [LexiconEntry]
    public var shortcuts: [ShortcutEntry]
    public var cleaner: CleanupService?
    public var grammarChecker: (any GrammarChecker)?
    public var grammarPolicy: GrammarGatePolicy

    public init(lexiconEntries: [LexiconEntry] = [], shortcuts: [ShortcutEntry] = [],
                cleaner: CleanupService? = nil, grammarChecker: (any GrammarChecker)? = nil,
                grammarPolicy: GrammarGatePolicy = .loadBundled()) {
        self.lexiconEntries = lexiconEntries
        self.shortcuts = shortcuts
        self.cleaner = cleaner
        self.grammarChecker = grammarChecker
        self.grammarPolicy = grammarPolicy
    }
}

/// Canonical stage order (PLAN section 9):
/// commands, shortcuts, numbers, lexicon, cleanup, numbers+lexicon assertion pass,
/// grammar gate, line format.
public enum TextPipelineBuilder {
    public static func make(settings: AppSettings,
                            dependencies: TextPipelineDependencies = TextPipelineDependencies()) -> TextPipeline {
        var stages: [any TextStage] = []
        if settings.commandsEnabled {
            stages.append(CommandsStage())
        }
        if !dependencies.shortcuts.isEmpty {
            stages.append(ShortcutsStage(entries: dependencies.shortcuts))
        }
        stages.append(NumbersStage(id: "numbers"))
        if settings.codeSpeakEnabled {
            stages.append(CodeSpeakStage())
        }
        stages.append(LexiconStage(entries: dependencies.lexiconEntries, id: "lexicon"))
        if settings.cleanupEnabled, let cleaner = dependencies.cleaner {
            stages.append(CleanupStage(service: cleaner))
        }
        stages.append(NumbersStage(id: "numbers.assert"))
        stages.append(LexiconStage(entries: dependencies.lexiconEntries, id: "lexicon.assert"))
        if settings.harperEnabled, let grammar = dependencies.grammarChecker {
            stages.append(GrammarGateStage(checker: grammar, policy: dependencies.grammarPolicy))
        }
        stages.append(LineFormatStage(settings: settings.lineFormat))

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
