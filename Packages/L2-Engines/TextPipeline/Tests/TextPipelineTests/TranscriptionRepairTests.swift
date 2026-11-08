import XCTest
import SuperflowKernel
import SuperflowTechDictionary
@testable import SuperflowTextPipeline

final class TranscriptionRepairTests: XCTestCase {
    func testMissingSpaceAfterPunctuation() {
        XCTAssertEqual(TranscriptionRepair.apply("I really miss you.Hey, I really miss you"),
                       "I really miss you. Hey, I really miss you")
    }

    func testDoubledCapital() {
        XCTAssertEqual(TranscriptionRepair.apply("II think few things"), "I think few things")
    }

    func testVersionSurvives() {
        XCTAssertEqual(TranscriptionRepair.apply("Opus 5.5"), "Opus 5.5")
    }

    func testRepeatedSentenceKeepsOne() {
        XCTAssertEqual(TranscriptionRepair.apply("This works well. This works well. Next idea."),
                       "This works well. Next idea.")
    }

    func testDistinctSentencesSurvive() {
        let input = "This works well. That works poorly. Next idea."
        XCTAssertEqual(TranscriptionRepair.apply(input), input)
    }

    func testProtectedLiteralUntouched() {
        var protected = Protected()
        protected.literals.insert("II")
        XCTAssertEqual(TranscriptionRepair.apply("II think", protected: protected), "II think")
    }

    func testPreCleanupModelNameNormalizesBeforeCleanup() async {
        let result = await PreCleanupModelNameStage().apply(
            TranscriptDraft(text: "use opus 5.5 and sonnet 5.5"), context: TextContext())
        XCTAssertEqual(result.text, "use Claude Opus 5.5 and Claude Sonnet 5.5")
    }

    func testNextgsNormalizesToNextJs() async {
        let pipeline = TextPipelineBuilder.make(settings: .default)
        let result = await pipeline.run("I want to learn NextGS and TypeScript", context: TextContext())
        XCTAssertTrue(result.text.contains("Next.js"), result.text)
        XCTAssertTrue(result.text.contains("TypeScript"), result.text)
    }

    func testHardwareTermsNormalize() async {
        let pipeline = TextPipelineBuilder.make(settings: .default)
        let result = await pipeline.run("keep the Raspberry Pi and the HomePod speaker", context: TextContext())
        XCTAssertTrue(result.text.contains("Raspberry Pi"), result.text)
        XCTAssertTrue(result.text.contains("HomePod"), result.text)
    }

    func testCasualStylingSkipsDeterministicCapitalize() async {
        var settings = AppSettings.default
        settings.cleanupStyling = "casual"
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let result = await pipeline.run("hmm im gonna be late", context: TextContext(settings: settings))
        XCTAssertFalse(result.text.isEmpty)
        // With no cleaner injected the deterministic formatter must still
        // respect casual styling instead of re-capitalizing the line.
        if let first = result.text.first {
            XCTAssertTrue(first.isLowercase || first == "-", "expected casual lowercase, got: \(result.text)")
        }
        XCTAssertFalse(result.text.hasSuffix("late."), "casual must not force final period: \(result.text)")
    }

    func testSemiFormalKeepsCapitalizeAndPeriod() async {
        var settings = AppSettings.default
        settings.cleanupStyling = "semi-formal"
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let result = await pipeline.run("hmm im gonna be late", context: TextContext(settings: settings))
        XCTAssertTrue(result.text.first?.isUppercase == true, result.text)
    }

    func testFixture3VibeCoding() async {
        let pipeline = TextPipelineBuilder.make(settings: .default)
        let result = await pipeline.run("Honestly, I do not vipe code. I never vipcode in my life. I'm a seniors AI engineer or you can call it agentic engineer. I do serious agentic engineering all day.", context: TextContext())
        XCTAssertTrue(result.text.contains("vibe code"), result.text)
        XCTAssertTrue(result.text.contains("vibe coded"), result.text)
        XCTAssertTrue(result.text.contains("agentic engineer"), result.text)
        XCTAssertFalse(result.text.contains("vipe"), result.text)
        XCTAssertFalse(result.text.contains("vipcode"), result.text)
    }

    func testWipeAndAgentOfVariants() async {
        let pipeline = TextPipelineBuilder.make(settings: .default)
        let result = await pipeline.run("here's heng I'm not a wipe coder okay I'm not a whipe coder. I'm a serious agent of engineer.", context: TextContext())
        XCTAssertTrue(result.text.contains("vibe coder"), result.text)
        XCTAssertTrue(result.text.contains("agentic engineer"), result.text)
        XCTAssertFalse(result.text.contains("wipe"), result.text)
        XCTAssertFalse(result.text.contains("agent of"), result.text)
    }

    func testAICasingWholeTokenOnly() {
        XCTAssertEqual(AIEraResolver.enforceCasing("it said the rain"), "it said the rain")
        XCTAssertEqual(AIEraResolver.enforceCasing("i am an ai engineer"), "i am an AI engineer")
        XCTAssertEqual(AIEraResolver.enforceCasing("ai works with llm and api and mcp and gpu"), "AI works with LLM and API and MCP and GPU")
    }

    func testNewTermNeedsNoCodeChange() {
        let custom = AIEraLexicon.Term(canonical: "vibecoding", category: "practice", meaning: "test term", casing: "lower", boost: 1, variants: ["vibe-coding"])
        let resolved = AIEraResolver.apply("i love vibe-coding", terms: [custom])
        XCTAssertTrue(resolved.text.contains("vibecoding"), resolved.text)
    }

    func testPipelineOrderRunsNormalizationBeforeCleanup() async {
        let pipeline = TextPipelineBuilder.make(settings: .default)
        let ids = pipeline.stageIDs
        let preModel = ids.firstIndex(of: "preCleanupModelNames")
        let cleanup = ids.firstIndex(of: "cleanup")
        let postModel = ids.firstIndex(of: "modelNames")
        XCTAssertNotNil(preModel)
        if let cleanup, let preModel { XCTAssertLessThan(preModel, cleanup) }
        if let cleanup, let postModel { XCTAssertGreaterThan(postModel, cleanup) }
    }
}
