import XCTest
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowTextPipeline

/// Focused gates for the verbatim official S1-mini v1 strings and for the
/// deterministic stages that must not corrupt them. Every expectation is an
/// exact value or an explicit forbidden token — a plausible paraphrase or a
/// superseded fact is a FAIL.
final class OfficialQualityTests: XCTestCase {

    // MARK: - Self-correction resolves to the final value only

    func testOfficialFridayNoWaitMakeThatThursday() {
        XCTAssertEqual(
            SelfCorrection.apply("so um i need to like send the the report by uh friday no wait make that thursday"),
            "so um i need to like send the the report by uh thursday")
    }

    func testOfficialFortyTwoNoSorryFortyThree() {
        XCTAssertEqual(
            SelfCorrection.apply("i think the answer is forty two no sorry forty three"),
            "i think the answer is forty three")
    }

    func testTimeRevisionKeepsOnlyFinalTimeAndDay() {
        XCTAssertEqual(
            SelfCorrection.apply("the meeting is at four p m on thursday actually no friday at five thirty"),
            "the meeting is at five thirty on friday")
    }

    func testAllExplicitRevisionCuesResolve() {
        let cases = [
            ("move it to friday actually no wednesday", "move it to wednesday"),
            ("call it forty two sorry forty three", "call it forty three"),
            ("ship on monday i mean tuesday", "ship on tuesday"),
            ("send it on friday no, thursday", "send it on thursday"),
            ("the deadline is march third no wait march fourth", "the deadline is march fourth"),
            ("answer is one twenty three make that one twenty four", "answer is one twenty four"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(SelfCorrection.apply(input), expected, input)
        }
    }

    func testContrastiveAndOrdinaryPhrasesSurvive() {
        let unchanged = [
            "I actually no longer need the report tomorrow",
            "not on Friday but on Thursday",
            "sorry I am late",
            "we need three not four backups",
            "no wait",
            "very very good",
        ]
        for input in unchanged {
            XCTAssertEqual(SelfCorrection.apply(input), input, input)
        }
    }

    func testProtectedSpanIsNotRevised() {
        let protected = Protected(literals: ["friday no wait make that thursday"])
        let input = "ship it friday no wait make that thursday"
        XCTAssertEqual(SelfCorrection.apply(input, protected: protected), input)
    }

    // MARK: - Full deterministic pipeline on the official numeric string

    func testOfficialNumericSelfCorrectionPipelineIsExact() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let result = await pipeline.run("i think the answer is forty two no sorry forty three",
                                        context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "I think the answer is 43.")
        XCTAssertFalse(result.text.localizedCaseInsensitiveContains("42"), result.text)
        XCTAssertFalse(result.text.localizedCaseInsensitiveContains("forty two"), result.text)
    }

    // MARK: - Disfluency keeps meaning and protected spans

    func testFillersAndStuttersRemovedButMeaningfulRepetitionKept() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let text = await pipeline.run(
            "um so like i i i need the the the report by uh friday no wait make that thursday very very no no",
            context: TextContext(settings: settings)).text
        for forbidden in [" um ", " uh ", "i i", "the the", "friday no wait", "make that thursday"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), "\(forbidden) in \(text)")
        }
        XCTAssertTrue(text.localizedCaseInsensitiveContains("thursday"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("very very"), "meaningful repeat lost: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("no no"), "negation repeat lost: \(text)")
    }

    func testFillerInsideProtectedSpanSurvives() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let result = await pipeline.run("um open uh and um close",
                                        context: TextContext(settings: settings),
                                        protected: Protected(literals: ["uh"]))
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("uh"), result.text)
        XCTAssertFalse(result.text.localizedCaseInsensitiveContains(" um "), result.text)
    }

    // MARK: - Final polish: casing, standalone I, final punctuation

    func testFinalPolishCasingStandaloneIAndFinalPeriod() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings)
        let text = await pipeline.run("i went home. then i left.",
                                      context: TextContext(settings: settings)).text
        XCTAssertEqual(text, "I went home. Then I left.")
    }

    // MARK: - Downstream stages preserve exact S1-mini output byte-for-byte

    private actor ExactCleaner: TextCleaner {
        let output: String
        init(_ output: String) { self.output = output }
        var isReady: Bool { true }
        func countTokens(_ text: String) async -> Int { text.split(separator: " ").count }
        func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
            CleanResult(text: output, tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 0)
        }
    }

    /// Feeds an exact S1-mini completion to the stages that run AFTER the model,
    /// the way production does. CleanGuard is deliberately bypassed because it
    /// validates a model against its own raw input, not an already-final string.
    private func polished(_ modelOutput: String) async -> String {
        var settings = AppSettings.default
        // Prose structure keeps the deterministic list shaper from re-inventing
        // layout the model already produced; blank-line structure must survive.
        settings.cleanupStructure = "prose"
        let built = TextPipelineBuilder.make(settings: settings)
        let preModel: Set<String> = [
            "selfCorrection", "preCleanupRepair", "aiEraPreCleanup", "preCleanupModelNames",
            "techDictionaryPreCleanup", "disfluency", "numbers", "cleanup",
        ]
        let pipeline = TextPipeline(stages: built.stages.filter { !preModel.contains($0.id) },
                                    seedProtected: built.seedProtected)
        return await pipeline.run(modelOutput, context: TextContext(settings: settings)).text
    }

    func testInvoiceCurrencyCommaIsPreserved() async {
        let official = "The invoice came to $23,450, and it's due on March 3, 2026."
        XCTAssertEqual(await polished(official), official)
    }

    func testEmailBlankLineLayoutIsPreserved() async {
        let official = "Hey Sarah,\n\nJust following up on the proposal.\n\nThanks, John."
        let text = await polished(official)
        XCTAssertTrue(text.contains("Hey Sarah,"), text)
        XCTAssertTrue(text.contains("\n\n"), "blank line between blocks was flattened: \(text)")
        XCTAssertTrue(text.contains("\n\nThanks, John."), text)
        XCTAssertFalse(text.contains("proposal. Thanks"), "body and sign-off were merged: \(text)")
    }

    func testOfficialListLayoutIsPreserved() async {
        let official = "For the trip, we need to pack\n\n- sunscreen\n- a first aid kit\n- chargers for everything."
        let text = await polished(official)
        XCTAssertTrue(text.contains("\n"), "list newlines were flattened: \(text)")
        let bullets = text.split(separator: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(bullets.count, 3, text)
        for item in ["sunscreen", "a first aid kit", "chargers for everything"] {
            XCTAssertTrue(text.localizedCaseInsensitiveContains(item), "\(item) lost: \(text)")
        }
    }

    func testFillerOnlyInputYieldsEmptyString() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        let pipeline = TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: ExactCleaner(""))))
        let result = await pipeline.run("um", context: TextContext(settings: settings))
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.draft.cleanupState, .cleaned)
    }
}
