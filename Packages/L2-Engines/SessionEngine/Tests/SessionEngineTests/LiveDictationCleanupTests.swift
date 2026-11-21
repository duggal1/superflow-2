import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

final class LiveDictationCleanupTests: XCTestCase {
    func testCheckpointRequiresLookaheadAndRetainsExactPunctuation() {
        let sentence = "Please review the technical report and send the approval today."
        XCTAssertNil(LiveDictationCleanup.checkpoint(in: sentence))
        XCTAssertEqual(LiveDictationCleanup.checkpoint(in: sentence + "  Next we can start."),
                       sentence)
        XCTAssertNil(LiveDictationCleanup.checkpoint(in: sentence + "  No wait tomorrow."))
    }

    func testReusesMatchingPrefixAndDiscardsRevisedPrefix() async {
        let sentence = "Please review the technical report and send the approval today."
        let pipeline = TextPipeline(stages: [AcceptedStage()])
        let cache = LiveDictationCleanup()
        let revision = UUID()
        let context = TextContext()
        let stream = sentence + "  Next we can start."
        await cache.offer(stream, revision: revision, pipeline: pipeline, context: context)
        await cache.waitForTesting()
        let matched = await cache.take(stream, revision: revision)
        XCTAssertEqual(matched?.prefix?.text, sentence)
        XCTAssertEqual(matched?.tail, "Next we can start.")

        await cache.offer(stream, revision: revision, pipeline: pipeline, context: context)
        await cache.waitForTesting()
        let revised = await cache.take(stream.replacingOccurrences(of: "today", with: "tomorrow"), revision: revision)
        XCTAssertNil(revised)
    }
}

private struct AcceptedStage: TextStage {
    let id = "accepted"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var result = draft
        result.cleanupState = .cleaned
        return result
    }
}
