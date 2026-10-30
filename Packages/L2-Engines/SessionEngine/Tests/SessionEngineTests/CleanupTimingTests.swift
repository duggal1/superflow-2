import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

final class CleanupTimingTests: XCTestCase {
    private actor TimingStage: SuperflowPorts.TextStage {
        nonisolated let id = "timing-recorder"
        private(set) var timings: [WordTiming] = []

        func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
            timings = context.wordTimings
            var output = draft
            output.cleanupState = .cleaned
            return output
        }
    }

    func testBoundedCleanupRequestCarriesTimingMetadataToPipeline() async throws {
        let repository = InMemoryRepository()
        let session = SessionRecord(kind: .dictation, modelProfile: "test")
        try await repository.createSession(session)
        try await repository.appendSegment(Segment(sessionID: session.id, index: 0, startMs: 0,
                                                    endMs: 1_000, source: .mic, rawText: "hello world"))
        let stage = TimingStage()
        let timings = [WordTiming(word: "hello", startMs: 0, endMs: 100),
                       WordTiming(word: "world", startMs: 800, endMs: 1_000)]
        let coordinator = SessionCleanupCoordinator(repository: repository, sessionID: session.id, emit: { _ in })
        await coordinator.start(workerCount: 1)
        await coordinator.submit(index: 0, interactive: true, pipeline: TextPipeline(stages: [stage]),
                                 settings: .default, wordTimings: timings)
        let state = await coordinator.finish()
        let received = await stage.timings
        XCTAssertEqual(state, .cleaned)
        XCTAssertEqual(received, timings)
    }
}
