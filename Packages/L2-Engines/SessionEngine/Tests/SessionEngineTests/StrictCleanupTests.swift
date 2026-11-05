import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

final class StrictCleanupTests: XCTestCase {
    func testModelFailureInsertsDeterministicallyFormattedTranscript() async throws {
        let repository = InMemoryRepository()
        let journals = FakeJournalStore()
        let inserter = RecordingInserter()
        let audio = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 80_000))
        let recognizer = FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 80_000)
        let pipeline = TextPipelineBuilder.make(settings: .default,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: FakeTextCleaner(.fail))))
        let engine = SessionEngine(audio: audio, recognizer: recognizer, pipeline: pipeline,
                                   repository: repository, journals: journals, inserter: inserter)
        let id = try await engine.start()
        _ = await engine.stop()
        let inserted = await inserter.inserted
        let samples = await journals.sampleCount(session: id, source: .mic)
        let state = await engine.currentState
        XCTAssertEqual(inserted.count, 1)
        XCTAssertTrue(inserted[0].lowercased().contains("hello world"), inserted[0])
        XCTAssertGreaterThan(samples, 0)
        XCTAssertEqual(state, .complete(id))
        let rows = try await repository.segments(session: id)
        XCTAssertTrue(rows.contains { $0.rawText == "hello world" && $0.cleanupState == .fallback })
        let saved = try await repository.session(id)
        XCTAssertEqual(saved?.status, .complete)
    }
    func testSlowModelTimesOutWithoutSkippingDeterministicDedupe() async throws {
        let repository = InMemoryRepository()
        let inserter = RecordingInserter()
        let recognizer = FakeSpeechRecognizer(script: ["we we need need to ship it"],
                                              samplesPerSegment: 80_000)
        let defaults = TextPipelineBuilder.make(settings: .default)
        let pipeline = TextPipeline(stages: [DelayedCleanupStage()] + defaults.stages)
        let engine = SessionEngine(
            audio: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 80_000)),
            recognizer: recognizer, pipeline: pipeline,
            repository: repository, journals: FakeJournalStore(), inserter: inserter)
        let id = try await engine.start()
        let result = await engine.stop()
        XCTAssertEqual(result?.cleanupState, .fallback)
        let inserted = await inserter.inserted
        let text = try XCTUnwrap(inserted.first)
        XCTAssertFalse(text.lowercased().contains("we we"), text)
        XCTAssertFalse(text.lowercased().contains("need need"), text)
        XCTAssertTrue(text.lowercased().contains("ship it"), text)
        try await Task.sleep(for: .milliseconds(100))
        let rows = try await repository.segments(session: id)
        XCTAssertFalse(rows.map(\.bestText).joined().contains("late overwrite"))
    }

    func testASRFailureDoesNotInsertPartialTranscript() async throws {
        let repository = InMemoryRepository()
        let journals = FakeJournalStore()
        let inserter = RecordingInserter()
        let audio = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 80_000))
        let pipeline = TextPipelineBuilder.make(settings: .default,
            dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: FakeTextCleaner(.identity))))
        let engine = SessionEngine(audio: audio, recognizer: FailingRecognizer(), pipeline: pipeline,
                                   repository: repository, journals: journals, inserter: inserter)
        let id = try await engine.start()
        _ = await engine.stop()
        let inserted = await inserter.inserted
        let samples = await journals.sampleCount(session: id, source: .mic)
        let state = await engine.currentState
        XCTAssertTrue(inserted.isEmpty)
        XCTAssertGreaterThan(samples, 0)
        guard case .failed = state else { return XCTFail("Expected failure, got \(state)") }
    }

}

private struct FailingRecognizer: SpeechRecognizer {
    let isReady = true
    func warmUp(profile: String) async throws {}
    func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        FakeRecognitionStream(script: ["partial transcript"], samplesPerSegment: 16_000, source: source, failEvery: 2)
    }
}

/// The worker is cancelled at the paste deadline and may ignore cancellation.
/// It must never overwrite what the user already received.
private struct DelayedCleanupStage: SuperflowPorts.TextStage {
    let id = "cleanup"
    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        try? await Task.sleep(for: .seconds(4))
        var result = draft
        result.text = "late overwrite"
        result.cleanupState = .cleaned
        return result
    }
}
