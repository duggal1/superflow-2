import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextGrammarGate
import SuperflowTextLineFormat
import SuperflowTextPipeline

private struct EraserStage: SuperflowPorts.TextStage {
    let id = "eraser"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var out = draft
        out.text = ""
        return out
    }
}

final class PipelineTests: XCTestCase {
    func testCompactModelSizeSurvivesCleanerDeletingIt() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: FakeTextCleaner(.dropLast))))
        let result = await pipeline.run("I need an extremely extremely fast model with zero point six billion",
                                        context: TextContext(settings: settings))
        XCTAssertTrue(result.text.contains("0.6B"), result.text)
        XCTAssertTrue(result.text.lowercased().contains("extremely extremely"), result.text)
    }
    private func dependencies(cleaner: FakeTextCleaner = FakeTextCleaner(.identity),
                              grammar: FakeGrammarChecker? = nil,
                              policy: GrammarGatePolicy = GrammarGatePolicy(maxEditRatio: 1.0, timeCapMs: 500))
        -> TextPipelineDependencies {
        TextPipelineDependencies(
            lexiconEntries: [
                LexiconEntry(kind: .term, triggers: ["next js"], canonical: "Next.js"),
                LexiconEntry(kind: .correction, triggers: ["super flow"], canonical: "Superflow"),
            ],
            shortcuts: [ShortcutEntry(trigger: "sign off", content: "# Notes\n\n- one\n- two")],
            cleaner: CleanupService(cleaner: cleaner),
            grammarChecker: grammar,
            grammarPolicy: policy)
    }

    private func allSettings() -> AppSettings {
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.harperEnabled = true
        return settings
    }

    func testCleanupRunsFirstAndHarperNeverRuns() {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        XCTAssertEqual(pipeline.stageIDs.first, "cleanup")
        XCTAssertFalse(pipeline.stageIDs.contains("grammar"))
    }

    func testCanonicalStageOrder() {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        XCTAssertEqual(pipeline.stageIDs, [
            "cleanup", "dedupe", "format", "commands", "shortcuts", "spokenCode", "numbers", "lexicon", "codeAware",
            "lineformat", "techDictionary",
        ])
    }

    func testOptionalStagesAreOmitted() {
        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings, dependencies: dependencies())
        XCTAssertEqual(pipeline.stageIDs,
                       ["dedupe", "format", "shortcuts", "spokenCode", "numbers", "lexicon", "codeAware", "lineformat",
                        "techDictionary"])
    }

    func testCodeSpeakIsOptInAndRunsAfterNumbers() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        XCTAssertFalse(TextPipelineBuilder.make(settings: settings, dependencies: dependencies())
            .stageIDs.contains("codeSpeak"))

        settings.codeSpeakEnabled = true
        let pipeline = TextPipelineBuilder.make(settings: settings, dependencies: dependencies())
        XCTAssertEqual(Array(pipeline.stageIDs.prefix(7)),
                       ["dedupe", "format", "commands", "shortcuts", "spokenCode", "numbers", "codeSpeak"])
        let index = pipeline.stageIDs.firstIndex(of: "codeSpeak")
        XCTAssertEqual(index.map { pipeline.stageIDs[$0 + 1] }, "lexicon")

        let result = await pipeline.run("snake case user id", context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "user_id")
    }

    func testDedupeAndCodeAwareRunBeforeLineFormat() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        let project = ProjectContext(root: FileManager.default.temporaryDirectory,
                                     paths: ["src/main.ts"], isCoding: true,
                                     approvedByUser: true)
        let pipeline = TextPipelineBuilder.make(
            settings: settings, dependencies: TextPipelineDependencies(project: project))
        let ids = pipeline.stageIDs
        XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: "dedupe")),
                          try XCTUnwrap(ids.firstIndex(of: "numbers")))
        XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: "lexicon")),
                          try XCTUnwrap(ids.firstIndex(of: "codeAware")))
        XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: "codeAware")),
                          try XCTUnwrap(ids.firstIndex(of: "lineformat")))
        let result = await pipeline.run("I I I want to open src slash main",
                                        context: TextContext(settings: settings, project: project))
        XCTAssertEqual(result.text, "I want to open src/main.ts")
    }

    func testShortcutExpandsVerbatimAndShortCircuits() async {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        let result = await pipeline.run("sign off", context: TextContext())
        XCTAssertEqual(result.text, "# Notes\n\n- one\n- two")
        XCTAssertEqual(result.shortCircuitedBy, "shortcuts")
        XCTAssertEqual(result.timings.last?.id, "shortcuts")
    }

    func testNumbersAndLexiconFollowCleanup() async {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        let result = await pipeline.run("i need two hundred dollars for next js", context: TextContext())
        XCTAssertTrue(result.text.contains("$200"), result.text)
        XCTAssertTrue(result.text.contains("Next.js"), result.text)
        let ids = result.timings.map(\.id)
        let cleanup = try? XCTUnwrap(ids.firstIndex(of: "cleanup"))
        let lexicon = try? XCTUnwrap(ids.firstIndex(of: "lexicon"))
        let assertion = try? XCTUnwrap(ids.firstIndex(of: "lineformat"))
        XCTAssertNotNil(cleanup)
        XCTAssertNotNil(lexicon)
        XCTAssertNotNil(assertion)
        if let cleanup, let lexicon, let assertion {
            XCTAssertLessThan(cleanup, lexicon)
            XCTAssertLessThan(cleanup, assertion)
        }
    }

    func testCleanupFailureKeepsTier0Text() async {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(cleaner: FakeTextCleaner(.fail),
                                                                           grammar: FakeGrammarChecker()))
        let result = await pipeline.run("keep this text please", context: TextContext())
        XCTAssertTrue(result.text.lowercased().contains("keep this text please"), result.text)
        XCTAssertEqual(result.draft.cleanupState, .fallback)
        XCTAssertTrue(result.draft.diagnostics.contains { $0.stage.hasPrefix("cleanup") })
    }

    /// S1-mini's empty result for filler-only input is a valid cleanup, not a
    /// stage failure. The pipeline must not revert it to the raw filler text.
    func testCleanupCanProduceAValidEmptyResultForFillerOnlyInput() async {
        let pipeline = TextPipelineBuilder.make(
            settings: allSettings(),
            dependencies: dependencies(cleaner: FakeTextCleaner(.empty),
                                       grammar: FakeGrammarChecker()))
        let result = await pipeline.run("um uh", context: TextContext())
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.draft.cleanupState, .cleaned)
        XCTAssertFalse(result.draft.diagnostics.contains { $0.message.contains("reverted") })
    }

    func testGrammarStageOnlyWhenEnabled() async {
        var settings = allSettings()
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings,
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        XCTAssertFalse(pipeline.stageIDs.contains("grammar"))
    }

    func testDictionaryTermsAreProtectedFromGrammar() async {
        let grammar = FakeGrammarChecker(lints: [
            GrammarLint(utf16Start: 0, utf16Length: 9, kind: "spelling", suggestion: "Super flow"),
        ])
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: grammar))
        let result = await pipeline.run("Superflow ships today", context: TextContext())
        XCTAssertTrue(result.text.hasPrefix("Superflow"), result.text)
    }

    func testRogueStageCannotEraseText() async {
        let pipeline = TextPipeline(stages: [EraserStage()])
        let result = await pipeline.run("keep me", context: TextContext())
        XCTAssertEqual(result.text, "keep me")
        XCTAssertTrue(result.draft.diagnostics.contains { $0.message.contains("reverted") })
    }

    func testEmptyInputStaysEmpty() async {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        let result = await pipeline.run("", context: TextContext())
        XCTAssertEqual(result.text, "")
    }

    func testPipelineIsDeterministic() async {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        let context = TextContext()
        let first = await pipeline.run("hello there. this is a test of the pipeline", context: context)
        let second = await pipeline.run("hello there. this is a test of the pipeline", context: context)
        XCTAssertEqual(first.text, second.text)
        XCTAssertEqual(first.draft.cleanupState, second.draft.cleanupState)
    }

    func testTechDictionaryIsAlwaysLast() {
        let pipeline = TextPipelineBuilder.make(settings: AppSettings.default, dependencies: dependencies())
        XCTAssertEqual(pipeline.stageIDs.last, "techDictionary")
        XCTAssertEqual(pipeline.stageIDs.dropLast().last, "lineformat")
        XCTAssertTrue(pipeline.stageIDs.contains("format"))
    }

    func testBundledTechDictionaryRunsAfterFormatting() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.commandsEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        let pipeline = TextPipelineBuilder.make(settings: settings,
                                                dependencies: TextPipelineDependencies())
        let result = await pipeline.run("use next js and git hub",
                                        context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "use Next.js and GitHub")
        XCTAssertEqual(result.timings.last?.id, "techDictionary")
    }

    func testFormattingShapesModelLikeListWithoutChangingWords() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        settings.commandsEnabled = false
        settings.lineFormat.capitalize = false
        settings.lineFormat.finalPeriod = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let input = "Grocery list 1. milk 2. eggs 3. bread"
        let result = await pipeline.run(input, context: TextContext(settings: settings))
        XCTAssertTrue(result.text.contains("1. milk\n2. eggs\n3. bread"), result.text)
        XCTAssertTrue(FormatGuard.preserves(input, result.text), result.text)
    }
}
