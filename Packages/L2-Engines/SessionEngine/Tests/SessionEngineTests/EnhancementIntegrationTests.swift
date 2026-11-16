import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
import XCTest
@testable import SuperflowSessionEngine

private actor GainEnhancer: SpeechEnhancer {
    func isAvailable() async -> Bool { true }
    func prepare() async throws {}
    func begin() async throws {}
    func process(_ samples: [Float]) async throws -> [Float] { samples.map { $0 * 0.5 } }
    func finish() async throws -> [Float] { [] }
    func reset() async {}
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
            // Speech-like alternating input: a DC step is legitimately removed
            // by the pre-ASR high-pass and would not exercise the level contract.
            let raw = (0..<3_201).map { index in
                0.2 * sin(2 * Float.pi * 200 * Float(index) / 16_000)
            }
            let engine = SessionEngine(audio: ScriptedAudioSource(samples: raw),
                recognizer: RecordingRecognizer(stream: recognition), pipeline: pipeline,
                repository: InMemoryRepository(), journals: journals, inserter: RecordingInserter(),
                settings: settings, enhancer: GainEnhancer())
            _ = try await engine.start()
            _ = await engine.stop()
            let journalChunks = await journals.chunks[.mic] ?? []
            let recognized = await recognition.chunks
            XCTAssertEqual(journalChunks.flatMap(\.samples), raw)
            let output = recognized.flatMap(\.samples)
            if enabled {
                // The enhancer halves the signal, then the session's AGC leveler
                // adjusts its amplitude. Check the actual contract rather than
                // expecting the pre-AGC samples to reach recognition unchanged.
                XCTAssertEqual(output.count, raw.count)
                XCTAssertTrue(output.allSatisfy(\.isFinite))
                XCTAssertLessThan(output.map(abs).max() ?? 0, 0.2)
                XCTAssertGreaterThan(output.filter { abs($0) > 0.01 }.count, output.count / 2)
            } else {
                // Disabling enhancement must bypass both denoising and AGC.
                XCTAssertEqual(output, raw)
            }
            XCTAssertEqual(recognized.last?.endSample, Int64(raw.count))
        }
    }
}
