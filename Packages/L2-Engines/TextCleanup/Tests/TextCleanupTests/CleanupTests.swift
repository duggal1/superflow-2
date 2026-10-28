import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowTextCleanup

final class CleanupTests: XCTestCase {
    private func service(_ cleaner: FakeTextCleaner, config: CleanupConfig = CleanupConfig()) -> CleanupService {
        CleanupService(cleaner: cleaner, config: config)
    }

    func testIdentityIsCleaned() async {
        let cleaner = FakeTextCleaner(.identity)
        let outcome = await service(cleaner).clean("hello world. this is fine.", context: TextContext())
        XCTAssertEqual(outcome.text, "hello world. this is fine.")
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertEqual(outcome.chunks.count, 1)
    }

    func testFailureFallsBackToTier0() async {
        let outcome = await service(FakeTextCleaner(.fail)).clean("keep this text", context: TextContext())
        XCTAssertEqual(outcome.text, "keep this text")
        XCTAssertEqual(outcome.state, .fallback)
    }

    /// S1-mini intentionally returns nothing for input that is only filler or
    /// noise. The pipeline must keep that empty result instead of restoring the
    /// raw filler text.
    func testFillerOnlyEmptyOutputIsCleaned() async {
        let outcome = await service(FakeTextCleaner(.empty)).clean("um uh", context: TextContext())
        XCTAssertEqual(outcome.text, "")
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertEqual(outcome.chunks.map(\.state), [.cleaned])
    }

    /// An empty completion for content-bearing input is still a failure.
    func testEmptyOutputForContentFallsBackToTier0() async {
        let outcome = await service(FakeTextCleaner(.empty)).clean("hello there", context: TextContext())
        XCTAssertEqual(outcome.text, "hello there")
        XCTAssertEqual(outcome.state, .fallback)
    }

    func testFillerOnlyDetection() {
        XCTAssertTrue(FillerOnlyText.isFillerOnly(""))
        XCTAssertTrue(FillerOnlyText.isFillerOnly("um uh"))
        XCTAssertTrue(FillerOnlyText.isFillerOnly("umm hmmm err"))
        XCTAssertTrue(FillerOnlyText.isFillerOnly("[noise] (inaudible) ♪"))
        XCTAssertFalse(FillerOnlyText.isFillerOnly("um hello"))
        XCTAssertFalse(FillerOnlyText.isFillerOnly("error"))
        XCTAssertFalse(FillerOnlyText.isFillerOnly("you know"))
    }

    func testTruncationFallsBack() async {
        let input = "one two three four five six seven eight nine ten eleven twelve"
        let outcome = await service(FakeTextCleaner(.truncate)).clean(input, context: TextContext())
        XCTAssertEqual(outcome.text, input)
        XCTAssertEqual(outcome.state, .fallback)
    }

    func testSlowFallsBackAtDeadline() async {
        var config = CleanupConfig()
        config.interactiveDeadlineMs = 40
        let start = Date()
        let outcome = await service(FakeTextCleaner(.slow(ms: 400)), config: config)
            .clean("hello world", context: TextContext())
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(outcome.state, .fallback)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testHallucinationFallsBack() async {
        let outcome = await service(FakeTextCleaner(.echoPrefix("totally invented preamble ")))
            .clean("real words here and more", context: TextContext())
        XCTAssertEqual(outcome.state, .fallback)
    }

    func testDisabledSkips() async {
        var settings = AppSettings.default
        settings.cleanupEnabled = false
        let outcome = await service(FakeTextCleaner(.upper))
            .clean("hello", context: TextContext(settings: settings))
        XCTAssertEqual(outcome.text, "hello")
        XCTAssertEqual(outcome.state, .skipped)
    }

    func testPlannerNeverExceedsHardCap() async {
        let planner = ChunkPlanner(config: CleanupConfig(softTokenTarget: 20, hardTokenCap: 30))
        let text = (1...120).map { "word\($0)" }.joined(separator: " ") + "."
        let plans = await planner.plan(text) { input in max(1, wordCount(input)) }
        XCTAssertGreaterThan(plans.count, 1)
        for plan in plans { XCTAssertLessThanOrEqual(plan.tokens, 30, plan.text) }
        XCTAssertEqual(plans.map(\.index), Array(0..<plans.count))
    }

    func testPlannerKeepsOrder() async {
        let planner = ChunkPlanner(config: CleanupConfig(softTokenTarget: 10, hardTokenCap: 20))
        let text = "First sentence here. Second sentence follows. Third sentence ends."
        let plans = await planner.plan(text) { input in max(1, wordCount(input)) }
        XCTAssertEqual(plans.map(\.text).joined(separator: " "), text)
    }

    func testListCuesNeverChangeProseControlLine() async {
        let cleaner = FakeTextCleaner(.identity)
        let outcome = await service(cleaner).clean(
            "Here are the steps first install it second run it third ship it", context: TextContext())
        let options = await cleaner.lastOptions
        XCTAssertEqual(options?.structure, "prose")
        XCTAssertEqual(options?.styling, "semi-casual")
        XCTAssertEqual(outcome.text, "Here are the steps:\n- install it\n- run it\n- ship it")
    }

    func testOrdinaryProseStaysProse() async {
        let cleaner = FakeTextCleaner(.identity)
        _ = await service(cleaner).clean("First I went home. Then I ate dinner.",
                                         context: TextContext())
        let options = await cleaner.lastOptions
        XCTAssertEqual(options?.structure, "prose")
    }

    func testConfiguredStructureIsNeverOverridden() {
        XCTAssertEqual(CleanupStructureDetector.structure(
            for: "First one. Second two. Third three.", configured: "bullets"), "bullets")
        XCTAssertEqual(CleanupStructureDetector.structure(
            for: "First one. Second two. Third three.", configured: "prose"), "list")
        XCTAssertEqual(CleanupStructureDetector.structure(
            for: "First one. Second two.", configured: "prose"), "prose")
        XCTAssertEqual(CleanupStructureDetector.structure(
            for: "- one\n- two\n- three", configured: "prose"), "list")
    }

    func testCodingProjectUpgradesCleanupContext() async {
        let cleaner = FakeTextCleaner(.identity)
        let project = ProjectContext(root: FileManager.default.temporaryDirectory,
                                     isCoding: true, approvedByUser: true)
        _ = await service(cleaner).clean("hero.tsx", context: TextContext(project: project))
        let options = await cleaner.lastOptions
        XCTAssertEqual(options?.context, "coding")
    }

    func testSeamRepair() {
        XCTAssertEqual(SeamRepair.stitch(["Hello world", "world again"]), "Hello world again")
        XCTAssertEqual(SeamRepair.stitch(["Hello", "World"]), "Hello World")
        XCTAssertEqual(SeamRepair.stitch(["Hello.", "World"]), "Hello. World")
    }

    func testStitchRespectsOrder() async {
        let cleaner = FakeTextCleaner(.upper)
        let config = CleanupConfig(softTokenTarget: 8, hardTokenCap: 14)
        let outcome = await service(cleaner, config: config)
            .clean("alpha beta gamma. delta epsilon zeta. eta theta iota.", context: TextContext())
        XCTAssertTrue(outcome.text.hasPrefix("ALPHA"))
        XCTAssertTrue(outcome.text.contains("IOTA"))
    }

    func testEveryChunkResolved() async {
        let config = CleanupConfig(softTokenTarget: 6, hardTokenCap: 12, retryDepth: 1)
        let outcome = await service(FakeTextCleaner(.fail), config: config)
            .clean("one two three. four five six. seven eight nine.", context: TextContext())
        XCTAssertTrue(outcome.chunks.allSatisfy { $0.state == .fallback })
        XCTAssertEqual(wordCount(outcome.text), 9)
    }

    // MARK: Seam overlap

    func testPlannerComposesSeamOverlapFromPreviousTail() async {
        let config = CleanupConfig(softTokenTarget: 20, hardTokenCap: 40)
        let sentences = (1...9).map { "sentence number \($0) has several words." }
        let text = sentences.joined(separator: " ")
        let plans = await ChunkPlanner(config: config).plan(text) { $0.split(separator: " ").count }
        XCTAssertEqual(plans.count, 3)
        // The overlap is the previous chunk's trailing sentence, re-shared as
        // the next chunk's opening, and counts into the hard cap.
        XCTAssertEqual(plans[1].overlap, sentences[2])
        XCTAssertEqual(plans[2].overlap, sentences[5])
        XCTAssertTrue(plans[1].text.hasPrefix(plans[1].overlap + " "))
        XCTAssertTrue(plans[1].text.hasSuffix(sentences[5]))
        XCTAssertLessThanOrEqual(plans[1].tokens, config.hardTokenCap)
        XCTAssertLessThanOrEqual(plans[2].tokens, config.hardTokenCap)
    }

    func testPlannerOverlapCanBeDisabled() async {
        let config = CleanupConfig(softTokenTarget: 20, hardTokenCap: 40, overlapPercent: 0)
        let sentences = (1...9).map { "sentence number \($0) has several words." }
        let plans = await ChunkPlanner(config: config)
            .plan(sentences.joined(separator: " ")) { $0.split(separator: " ").count }
        XCTAssertTrue(plans.allSatisfy { $0.overlap.isEmpty })
    }

    /// The end-to-end invariant: with a cleaner that returns its input
    /// unchanged, overlap + dedupe must reproduce the original text exactly —
    /// the overlap adds context for the model, the assembly removes it again.
    func testIdentityCleanerReproducesInputAcrossOverlappedChunks() async {
        let config = CleanupConfig(softTokenTarget: 24, hardTokenCap: 60)
        let sentences = (1...8).map { "the quick brown fox jumps over fence number \($0)." }
        let input = sentences.joined(separator: " ")
        let outcome = await service(FakeTextCleaner(.identity), config: config)
            .clean(input, context: TextContext())
        XCTAssertEqual(outcome.state, .cleaned)
        XCTAssertGreaterThan(outcome.chunks.count, 1)
        XCTAssertEqual(outcome.text, input)
    }

    /// An identity cleaner only satisfies the invariant because the stitcher
    /// removes the overlap; this pins the removal directly on a normalized
    /// variant the model could realistically produce (different casing).
    func testStitcherDedupesOverlapAcrossCasing() {
        let stitched = OrderedStitcher.stitch(
            ["I sent the report said forty two words.",
             "The report said forty two words today"],
            overlaps: [nil, "the report said forty two words"])
        XCTAssertEqual(stitched, "I sent the report said forty two words. today")
    }

    func testStitcherKeepsUnmatchedSeams() {
        let stitched = OrderedStitcher.stitch(
            ["Alpha beta gamma.", "Delta epsilon zeta"],
            overlaps: [nil, "alpha beta"])
        XCTAssertEqual(stitched, "Alpha beta gamma. Delta epsilon zeta")
    }

    /// List lines never merge at a seam, with or without overlap metadata.
    func testStitcherJoinsListSeamsWithNewline() {
        XCTAssertEqual(OrderedStitcher.stitch(["- one\n- two", "- three"]),
                       "- one\n- two\n- three")
        XCTAssertEqual(OrderedStitcher.stitch(["- one\n- two", "- three"],
                                              overlaps: [nil, nil]),
                       "- one\n- two\n- three")
    }

    // MARK: Control-line carry-over

    private actor RecordingCleaner: TextCleaner {
        private(set) var byInput: [String: CleanOptions] = [:]
        var isReady: Bool { true }

        func countTokens(_ text: String) async -> Int {
            max(1, Tokenizer.words(in: text).count)
        }

        func clean(_ text: String, options: CleanOptions) async throws -> CleanResult {
            byInput[text] = options
            return CleanResult(text: text, tokensIn: 1, tokensOut: 1, hitTokenCap: false, latencyMs: 1)
        }
    }

    func testListsArePlannedBeforeChunksAndControlsStayConstant() async {
        let cleaner = RecordingCleaner()
        let config = CleanupConfig(softTokenTarget: 12, hardTokenCap: 24)
        let service = CleanupService(cleaner: cleaner, config: config)
        let text = "first alpha beta gamma. second delta epsilon zeta. third eta theta iota. "
            + "fourth kappa lambda mu. the overflowed garden stays open tonight regardless. "
            + "the garden gate stays open far too late."
        let outcome = await service.clean(text, context: TextContext())
        let options = await cleaner.byInput
        XCTAssertTrue(options.values.allSatisfy { $0.structure == "prose" })
        XCTAssertEqual(options["alpha beta gamma."]?.styling, "semi-casual")
        XCTAssertEqual(options["delta epsilon zeta."]?.styling, "semi-casual")
        XCTAssertEqual(options["eta theta iota."]?.styling, "semi-casual")
        XCTAssertEqual(options["kappa lambda mu."]?.styling, "semi-casual")
        XCTAssertTrue(outcome.text.hasPrefix("- alpha beta gamma\n- delta epsilon zeta\n- eta theta iota\n- kappa lambda mu"))
        XCTAssertTrue(outcome.text.contains("the garden gate stays open far too late."))
    }
}
