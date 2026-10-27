import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextGrammarGate
import SuperflowTextPipeline
import XCTest

final class PipelineGoldenTests: XCTestCase {
    private func fixture() throws -> CaseFixture {
        try Golden.load("pipeline/cases.json")
    }

    private var lexicon: [LexiconEntry] {
        [LexiconEntry(kind: .correction, triggers: ["super flow"], canonical: "Superflow")]
    }

    private var shortcuts: [ShortcutEntry] {
        [ShortcutEntry(trigger: "sign off", content: "# Notes\n\n- one\n- two")]
    }

    private func baseSettings() throws -> AppSettings {
        let fixture = try fixture()
        return Golden.stageSettings(SettingsPatch(
            commandsEnabled: true,
            cleanupEnabled: false,
            harperEnabled: false,
            spellOutSmallNumbers: nil,
            numberStyle: nil,
            lineFormat: LineFormatPatch(minWords: nil, preferredMax: nil, hardMax: nil,
                                        breakStyle: nil, capitalize: true, collapseSpaces: nil,
                                        fixPunctuationSpacing: nil, finalPeriod: true, trailingSpace: nil)
        ))
    }

    func testPipelineCorpus() async throws {
        let fixture = try fixture()
        let settings = try baseSettings()
        for c in fixture.cases {
            let applied = c.settings?.apply(to: settings) ?? settings
            let pipeline = Golden.makePipeline(settings: applied, lexicon: lexicon, shortcuts: shortcuts)
            let result = await pipeline.run(c.input, context: TextContext(settings: applied))
            assertGolden(result.text, c.expected, name: c.name)
        }
    }

    func testPipelinePreservesGroupedNumbersAndURLs() async throws {
        let fixture = try fixture()
        let settings = try baseSettings()
        for c in fixture.edgeCases ?? [] {
            let applied = c.settings?.apply(to: settings) ?? settings
            let pipeline = Golden.makePipeline(settings: applied, lexicon: lexicon, shortcuts: shortcuts)
            let result = await pipeline.run(c.input, context: TextContext(settings: applied))
            assertGolden(result.text, c.expected, name: c.name)
        }
    }

    func testStageOrderMatchesThePlan() async throws {
        var settings = try baseSettings()
        settings.cleanupEnabled = true
        settings.harperEnabled = true
        let pipeline = Golden.makePipeline(
            settings: settings,
            lexicon: lexicon,
            shortcuts: shortcuts,
            cleaner: CleanupService(cleaner: FakeTextCleaner(.identity)),
            grammar: FakeGrammarChecker(),
            grammarPolicy: .default
        )
        XCTAssertEqual(pipeline.stageIDs,
                       ["commands", "shortcuts", "numbers", "lexicon", "cleanup",
                        "numbers.assert", "lexicon.assert", "grammar", "lineformat"])
    }

    func testShortcutShortCircuitsEveryLaterStage() async throws {
        var settings = try baseSettings()
        settings.cleanupEnabled = true
        settings.harperEnabled = true
        let cleaner = FakeTextCleaner(.upper)
        let checker = FakeGrammarChecker()
        let pipeline = Golden.makePipeline(
            settings: settings,
            lexicon: lexicon,
            shortcuts: shortcuts,
            cleaner: CleanupService(cleaner: cleaner),
            grammar: checker
        )
        let result = await pipeline.run("sign off", context: TextContext(settings: settings))
        XCTAssertEqual(result.shortCircuitedBy, "shortcuts")
        XCTAssertEqual(result.text, "# Notes\n\n- one\n- two")
        let cleanerCalls = await cleaner.calls
        let checkerCalls = await checker.calls
        XCTAssertEqual(cleanerCalls, 0)
        XCTAssertEqual(checkerCalls, 0)
        XCTAssertFalse(result.timings.contains { $0.id == "lineformat" })
    }

    func testDictionaryCanonicalFormIsProtectedFromGrammar() async throws {
        var settings = try baseSettings()
        settings.harperEnabled = true
        let text = "Superflow"
        let lint = GrammarLint(utf16Start: 0, utf16Length: 9, kind: "spelling", suggestion: "Super flow")
        let pipeline = Golden.makePipeline(
            settings: settings,
            lexicon: lexicon,
            grammar: FakeGrammarChecker(lints: [lint]),
            grammarPolicy: GrammarGatePolicy(maxEditRatio: 1)
        )
        let result = await pipeline.run(text, context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "Superflow")
    }

    func testEmptyInputNeverCrashesOrProducesText() async throws {
        let settings = try baseSettings()
        let pipeline = Golden.makePipeline(settings: settings, lexicon: lexicon, shortcuts: shortcuts)
        for input in ["", "   ", "\n\n"] {
            let result = await pipeline.run(input, context: TextContext(settings: settings))
            XCTAssertEqual(result.text, "")
        }
    }

    func testCleanupRunsBeforeTheAssertionPass() async throws {
        var settings = try baseSettings()
        settings.cleanupEnabled = true
        let pipeline = Golden.makePipeline(
            settings: settings,
            lexicon: lexicon,
            cleaner: CleanupService(cleaner: FakeTextCleaner(.upper))
        )
        let result = await pipeline.run("the quick brown fox jumps over the lazy dog",
                                        context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG.")
        XCTAssertEqual(result.draft.cleanupState, .cleaned)
    }

    func testStageTimingsAreRecordedInOrder() async throws {
        let settings = try baseSettings()
        let pipeline = Golden.makePipeline(settings: settings, lexicon: lexicon, shortcuts: shortcuts)
        let result = await pipeline.run("hello world", context: TextContext(settings: settings))
        XCTAssertEqual(result.timings.map(\.id), pipeline.stageIDs)
        XCTAssertTrue(result.timings.allSatisfy { $0.ms >= 0 })
    }
}
