import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
import XCTest
@testable import SuperflowSessionEngine

private actor GainEnhancer: SpeechEnhancer {
    func isAvailable() -> Bool { true }
    func prepare(progress: @escaping @Sendable (Double) -> Void) { progress(1) }
    func begin() {}
    func process(_ samples: [Float]) -> [Float] { samples.map { $0 * 0.5 } }
    func finish() -> [Float] { [] }
    func reset() {}
}

private actor RecordingRecognition: RecognitionStream {
    nonisolated let events: AsyncStream<RecognitionEvent>
    let sink: AsyncStream<RecognitionEvent>.Continuation
    var chunks: [AudioChunk] = []
    init() { (events, sink) = AsyncStream.makeStream() }
    func feed(_ chunk: AudioChunk) { chunks.append(chunk) }
    func finish() { sink.finish() }
}

private struct RecordingRecognizer: SpeechRecognizer {
    let stream: RecordingRecognition
    var isReady: Bool { true }
    func warmUp(profile: String) {}
    func makeStream(profile: String, source: AudioSourceKind) -> any RecognitionStream { stream }
}

final class EnhancementIntegrationTests: XCTestCase, @unchecked Sendable {
    func testRawJournalPrecedesEnhancedRecognitionAndToggleBypasses() async throws {
        for enabled in [true, false] {
            let journals = FakeJournalStore()
            let recognition = RecordingRecognition()
            var settings = AppSettings()
            settings.keepJournals = true
            settings.keepAudio = false
            settings.cleanupEnabled = false
            settings.speechEnhancementEnabled = enabled
            let pipeline = TextPipelineBuilder.make(settings: settings, dependencies: TextPipelineDependencies())
            let raw = [Float](repeating: 0.2, count: 3_201)
            let engine = SessionEngine(audio: ScriptedAudioSource(samples: raw),
                recognizer: RecordingRecognizer(stream: recognition), pipeline: pipeline,
                repository: InMemoryRepository(), journals: journals, inserter: RecordingInserter(),
                settings: settings, enhancer: GainEnhancer())
            _ = try await engine.start()
            _ = await engine.stop()
            let journalChunks = await journals.chunks[.mic] ?? []
            let recognized = await recognition.chunks
            XCTAssertEqual(journalChunks.flatMap(\.samples), raw)
            XCTAssertEqual(recognized.flatMap(\.samples), enabled ? raw.map { $0 * 0.5 } : raw)
            XCTAssertEqual(recognized.last?.endSample, Int64(raw.count))
        }
    }
}
