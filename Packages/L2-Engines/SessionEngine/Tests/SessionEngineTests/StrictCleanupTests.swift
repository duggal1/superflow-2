import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

final class StrictCleanupTests: XCTestCase {
    func testModelFailureInsertsRawTranscriptAndKeepsRecording() async throws {
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
        XCTAssertEqual(inserted, ["hello world"])
        XCTAssertGreaterThan(samples, 0)
        XCTAssertEqual(state, .complete(id))
        let rows = try await repository.segments(session: id)
        XCTAssertTrue(rows.contains { $0.rawText == "hello world" && $0.cleanupState == .fallback })
        let saved = try await repository.session(id)
        XCTAssertEqual(saved?.status, .complete)
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
