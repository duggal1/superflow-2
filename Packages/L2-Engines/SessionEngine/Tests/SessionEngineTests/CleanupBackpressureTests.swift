import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

private struct SlowCleanupStage: SuperflowPorts.TextStage {
    let id = "slow-cleanup"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        // Models can take seconds or fail to return. Cancellation must not
        // cause a late cleanup write after the caller has already pasted text.
        try? await Task.sleep(for: .seconds(3))
        var result = draft
        result.text = "unwanted late rewrite"
        result.cleanupState = .cleaned
        return result
    }
}

private actor CounterProbe {
    private(set) var calls = 0
    func count(_ text: String) -> Int {
        calls += 1
        return text.count
    }
}

final class CleanupBackpressureTests: XCTestCase {
    func testCleanupQueueNeverBlocksRecognitionOnASlowModel() async throws {
        let repository = InMemoryRepository()
        let session = SessionRecord(kind: .dictation, modelProfile: "test")
        try await repository.createSession(session)
        let pipeline = TextPipeline(stages: [SlowCleanupStage()])
        let coordinator = SessionCleanupCoordinator(repository: repository, sessionID: session.id, emit: { _ in })
        await coordinator.start(workerCount: 2)
        let started = Date()
        var rejected = 0
        for index in 0..<140 {
            try await repository.appendSegment(Segment(
                sessionID: session.id, index: index, startMs: index * 1_000,
                endMs: (index + 1) * 1_000, source: .mic, rawText: "word \(index)"))
            let accepted = await coordinator.submit(
                index: index, interactive: true, pipeline: pipeline, settings: .default)
            if !accepted { rejected += 1 }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5,
                          "ASR must not wait for any S1-mini completion or queue slot")
        XCTAssertGreaterThan(rejected, 0, "The cleanup backlog must remain bounded")
        let stopped = Date()
        let outcome = await coordinator.finish(maximumWaitMs: 40)
        XCTAssertEqual(outcome, .fallback)
        XCTAssertLessThan(Date().timeIntervalSince(stopped), 1.0)
        try await Task.sleep(for: .milliseconds(100))
        let first = try await repository.segmentForProcessing(session: session.id, index: 0)
        XCTAssertEqual(first?.bestText, "word 0", "Timed-out workers must not write a late rewrite")
    }

    func testRecognitionDoesNotCallTheS1TokenizerToChooseQueuePriority() async throws {
        let probe = CounterProbe()
        let repository = InMemoryRepository()
        let engine = SessionEngine(
            audio: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 16_000)),
            recognizer: FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 8_000),
            pipeline: TextPipeline(stages: [], tokenCounter: { text in await probe.count(text) }),
            repository: repository, journals: FakeJournalStore(), inserter: RecordingInserter())
        _ = try await engine.start()
        let outcome = await engine.stop()
        XCTAssertEqual(outcome?.insertion, .pasted)
        let calls = await probe.calls
        XCTAssertEqual(calls, 0, "Recognizer event delivery must not depend on helper token counts")
    }
}
