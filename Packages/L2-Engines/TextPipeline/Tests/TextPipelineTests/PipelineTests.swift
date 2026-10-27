import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextGrammarGate
import SuperflowTextLineFormat
import SuperflowTextPipeline

private struct EraserStage: TextStage {
    let id = "eraser"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var out = draft
        out.text = ""
        return out
    }
}

final class PipelineTests: XCTestCase {
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

    func testCanonicalStageOrder() {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        XCTAssertEqual(pipeline.stageIDs, [
            "commands", "shortcuts", "numbers", "lexicon", "cleanup",
            "numbers.assert", "lexicon.assert", "grammar", "lineformat",
        ])
    }

    func testOptionalStagesAreOmitted() {
        var settings = AppSettings.default
        settings.commandsEnabled = false
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings, dependencies: dependencies())
        XCTAssertEqual(pipeline.stageIDs,
                       ["shortcuts", "numbers", "lexicon", "numbers.assert", "lexicon.assert", "lineformat"])
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
        XCTAssertEqual(Array(pipeline.stageIDs.prefix(4)),
                       ["commands", "shortcuts", "numbers", "codeSpeak"])
        let index = pipeline.stageIDs.firstIndex(of: "codeSpeak")
        XCTAssertEqual(index.map { pipeline.stageIDs[$0 + 1] }, "lexicon")

        let result = await pipeline.run("snake case user id", context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "user_id")
    }

    func testShortcutExpandsVerbatimAndShortCircuits() async {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        let result = await pipeline.run("sign off", context: TextContext())
        XCTAssertEqual(result.text, "# Notes\n\n- one\n- two")
        XCTAssertEqual(result.shortCircuitedBy, "shortcuts")
        XCTAssertEqual(result.timings.last?.id, "shortcuts")
    }

    func testNumbersAndLexiconRunAroundCleanup() async {
        let pipeline = TextPipelineBuilder.make(settings: allSettings(),
                                                dependencies: dependencies(grammar: FakeGrammarChecker()))
        let result = await pipeline.run("i need two hundred dollars for next js", context: TextContext())
        XCTAssertTrue(result.text.contains("$200"), result.text)
        XCTAssertTrue(result.text.contains("Next.js"), result.text)
        let ids = result.timings.map(\.id)
        let cleanup = try? XCTUnwrap(ids.firstIndex(of: "cleanup"))
        let lexicon = try? XCTUnwrap(ids.firstIndex(of: "lexicon"))
        let assertion = try? XCTUnwrap(ids.firstIndex(of: "lexicon.assert"))
        XCTAssertNotNil(cleanup)
        XCTAssertNotNil(lexicon)
        XCTAssertNotNil(assertion)
        if let cleanup, let lexicon, let assertion {
            XCTAssertLessThan(lexicon, cleanup)
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

    func testLineFormatIsAlwaysLast() {
        let pipeline = TextPipelineBuilder.make(settings: AppSettings.default, dependencies: dependencies())
        XCTAssertEqual(pipeline.stageIDs.last, "lineformat")
    }
}
