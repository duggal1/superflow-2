import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

final class SessionLatencyTests: XCTestCase {
    func testStopTimingIncludesTheInsertionCall() async throws {
        let metrics = RecordingMetrics()
        let inserter = RecordingInserter()
        await inserter.setAutoDelay(ms: 30)
        let engine = make(metrics: metrics, inserter: inserter)
        _ = try await engine.start()
        _ = await engine.stop()
        let before = metrics.records.first { $0.0 == "session.stop.ms" }?.1 ?? 0
        let inserted = try XCTUnwrap(metrics.records.first { $0.0 == "session.stop.to_insert_return.ms" }?.1)
        XCTAssertGreaterThanOrEqual(inserted - before, 20)
        XCTAssertEqual(metrics.records.filter { $0.0 == "session.mic_start.to_first_feed.ms" }.count, 1)
    }

    func testInsertionPrecedesArchiveAndHistoryFinalize() async throws {
        let metrics = RecordingMetrics()
        let inserter = RecordingInserter()
        let repository = InMemoryRepository()
        let engine = SessionEngine(audio: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 16_000)),
                                   recognizer: FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 8_000),
                                   pipeline: TextPipeline(stages: []), repository: repository,
                                   journals: FakeJournalStore(), inserter: inserter, metrics: metrics)
        _ = try await engine.start()
        let outcome = await engine.stop()
        XCTAssertEqual(outcome?.insertion, .pasted)
        let insertedAt = try XCTUnwrap(metrics.records.firstIndex { $0.0 == "session.stop.to_insert_return.ms" })
        let finalizedAt = try XCTUnwrap(metrics.records.firstIndex { $0.0 == "session.finalize.ms" })
        XCTAssertLessThan(insertedAt, finalizedAt)
        // The paste happened before the session row was marked complete, so a
        // crash in between leaves an unfinished session whose text recovery
        // shows without ever pasting it again.
        let saved = try await repository.session(outcome!.sessionID)
        XCTAssertEqual(saved?.status, .complete)
    }

    func testFailedInsertionDoesNotReportSuccessfulInsertionTiming() async throws {
        let metrics = RecordingMetrics()
        let inserter = RecordingInserter()
        await inserter.setOutcome(.blockedSecureField)
        let engine = make(metrics: metrics, inserter: inserter)
        _ = try await engine.start()
        _ = await engine.stop()
        XCTAssertFalse(metrics.records.contains { $0.0 == "session.stop.to_insert_return.ms" })
        XCTAssertTrue(metrics.records.contains { $0.0 == "session.stop.insertion_attempt.ms" })
    }

    private func make(metrics: RecordingMetrics, inserter: RecordingInserter) -> SessionEngine {
        SessionEngine(audio: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 16_000)),
                      recognizer: FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 8_000),
                      pipeline: TextPipeline(stages: []), repository: InMemoryRepository(),
                      journals: FakeJournalStore(), inserter: inserter, metrics: metrics)
    }
}
