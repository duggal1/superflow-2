import Foundation
import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

private struct SlowMarkingStage: SuperflowPorts.TextStage {
    let id = "slow-mark"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        try? await Task.sleep(for: .milliseconds(800))
        var result = draft
        result.text = "CLEAN " + draft.text
        result.cleanupState = .cleaned
        return result
    }
}

final class InsertionBudgetTests: XCTestCase {
    func testInsertionWaitsOnlyBrieflyForSlowCleanupWhichStillFinishes() async throws {
        let repository = InMemoryRepository()
        let inserter = RecordingInserter()
        let metrics = RecordingMetrics()
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.harperEnabled = false
        let engine = SessionEngine(
            audio: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 8_000)),
            recognizer: FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 8_000),
            pipeline: TextPipeline(stages: [SlowMarkingStage()]),
            repository: repository, journals: FakeJournalStore(), inserter: inserter,
            settings: settings, metrics: metrics, streamingCleanupEnabled: true)

        _ = try await engine.start()
        let outcome = await engine.stop()

        let insertMs = try XCTUnwrap(metrics.records.last { $0.0 == "session.stop.to_insert_return.ms" }?.1)
        XCTAssertLessThan(insertMs, 500, "Insertion must not wait for the full slow cleanup")
        let inserted = await inserter.inserted
        XCTAssertEqual(inserted, ["hello world"], "Unfinished cleanup must fall back to raw text")
        let sessionID = try XCTUnwrap(outcome?.sessionID)
        let segments = try await repository.segments(session: sessionID)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].cleanupState, .cleaned, "Cleanup must finish before stop returns")
        XCTAssertEqual(segments[0].bestText, "CLEAN hello world")
    }
}
