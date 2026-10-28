import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowMeetingEngine

final class MeetingTimingTests: XCTestCase {
    private actor TimingStage: TextStage {
        nonisolated let id = "timing-recorder"
        private(set) var timings: [WordTiming] = []

        func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
            timings = context.wordTimings
            var output = draft
            output.cleanupState = .cleaned
            return output
        }
    }

    func testCommittedMeetingTurnPassesRealWordTimingsToPipeline() async throws {
        let stage = TimingStage()
        let engine = MeetingEngine(mic: ScriptedAudioSource(samples: []), system: nil,
                                   recognizer: FakeSpeechRecognizer(script: []),
                                   pipeline: TextPipeline(stages: [stage]),
                                   repository: InMemoryRepository(), journals: FakeJournalStore())
        let session = try await engine.start()
        let timings = [WordTiming(word: "hello", startMs: 0, endMs: 100),
                       WordTiming(word: "world", startMs: 800, endMs: 1_000)]
        let raw = RawSegment(text: "hello world", startSample: 0, endSample: 16_000,
                             words: timings, source: .mic)
        await engine.persist(raw, source: .mic, session: session)
        _ = await engine.stop()
        let received = await stage.timings
        XCTAssertEqual(received, timings)
    }
}
