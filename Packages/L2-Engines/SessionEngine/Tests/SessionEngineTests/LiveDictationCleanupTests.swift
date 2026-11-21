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

    func testThirtyMinuteTranscriptKeepsOfferingCheckpointsBeyondPreviousPieceLimit() async {
        let sentences = (0..<450).map {
            "Review technical item number \($0) and approve before lunch today."
        }
        let cache = LiveDictationCleanup()
        let revision = UUID()
        let pipeline = TextPipeline(stages: [AcceptedStage()])
        var stream = ""

        for sentence in sentences {
            stream = stream.isEmpty ? sentence : stream + " " + sentence
            await cache.offer(stream, revision: revision, pipeline: pipeline, context: TextContext())
            await cache.waitForTesting()
        }

        let prepared = await cache.take(stream, revision: revision)
        XCTAssertEqual(stream.split(whereSeparator: \.isWhitespace).count, 4_500)
        XCTAssertEqual(prepared?.prefix?.text, sentences.dropLast().joined(separator: " "))
        XCTAssertEqual(prepared?.tail, sentences.last)
    }

    func testCorrectionAtTheLiveTailKeepsItsPrecedingSentenceForFinalCleanup() async {
        let sentences = (0..<60).map {
            "We should review design item number \($0) and approve this change before lunch today."
        }
        let cache = LiveDictationCleanup()
        let revision = UUID()
        let pipeline = TextPipeline(stages: [AcceptedStage()])
        var stream = ""

        for sentence in sentences {
            stream = stream.isEmpty ? sentence : stream + " " + sentence
            await cache.offer(stream, revision: revision, pipeline: pipeline, context: TextContext())
            await cache.waitForTesting()
        }

        let correction = "No wait make that item number 58 tomorrow."
        let corrected = sentences.dropLast().joined(separator: " ") + " " + correction
        await cache.offer(corrected, revision: revision, pipeline: pipeline, context: TextContext())

        let prepared = await cache.take(corrected, revision: revision)
        XCTAssertEqual(prepared?.prefix?.text, sentences.dropLast(2).joined(separator: " "))
        XCTAssertEqual(prepared?.tail, sentences[sentences.count - 2] + " " + correction)
    }

    func testFallbackResultDisablesReuseForTheWholePendingPrefix() async {
        let sentences = (0..<5).map {
            "Review technical item number \($0) and approve before lunch today."
        }
        let stream = sentences.joined(separator: " ")
        let cache = LiveDictationCleanup()
        let revision = UUID()

        await cache.offer(stream, revision: revision,
                          pipeline: TextPipeline(stages: [FallbackStage()]), context: TextContext())
        await cache.waitForTesting()

        let prepared = await cache.take(stream, revision: revision)
        XCTAssertNil(prepared)
    }
}

private struct AcceptedStage: SuperflowPorts.TextStage {
    let id = "accepted"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var result = draft
        result.cleanupState = .cleaned
        return result
    }
}

private struct FallbackStage: SuperflowPorts.TextStage {
    let id = "fallback"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var result = draft
        result.cleanupState = .fallback
        return result
    }
}
