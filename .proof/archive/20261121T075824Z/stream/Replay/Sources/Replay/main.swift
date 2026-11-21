import AVFoundation
import Foundation
import SuperflowAudioCpp
import SuperflowKernel
import SuperflowLLMCore
import SuperflowLLMLlamaCpp
import SuperflowPorts
import SuperflowSessionEngine
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline

private actor ReplayAudio: AudioSource {
    nonisolated let kind: AudioSourceKind = .mic
    private let frames = AsyncStream<AudioChunk>.makeStream()
    private let status = AsyncStream<AudioEvent>.makeStream()

    func start() async throws -> AudioStreams {
        AudioStreams(samples: frames.stream, events: status.stream)
    }

    func send(_ samples: [Float], offset: Int) {
        frames.continuation.yield(AudioChunk(samples: samples, startSample: Int64(offset), source: kind))
    }

    func stop() async {
        frames.continuation.finish()
        status.continuation.finish()
    }
}

private struct LocalModel: ModelProvider {
    let url: URL
    func localURL(for profileID: String) async -> URL? { url }
    func ensure(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
    func llmModelURL() async -> URL? { url }
    func ensureLLM(progress: @escaping @Sendable (Double) -> Void) async throws -> URL { url }
}

@main struct Replay {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 6, let sessions = Int(args[3]), let pace = Double(args[4]), pace > 0,
              let repeats = Int(args[5]), repeats > 0 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
        guard file.processingFormat.channelCount == 1, file.processingFormat.sampleRate == 16_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw CocoaError(.fileReadCorruptFile) }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        LlamaLogging.silence()
        let installed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf")
        let runtime = LlamaCppRuntime(sessions: sessions)
        let cleaner = LlamaCleaner(modelProvider: LocalModel(url: installed), runtime: runtime)
        try await cleaner.prepare(compute: .gpu)
        let recognizer = AudioCppRecognizer(modelCacheRoot: URL(fileURLWithPath: ".models/audio-cpp"))
        var settings = AppSettings.default
        settings.asrProfile = ModelProfile.nemotron35Streaming.id
        settings.cleanupEnabled = true
        try await recognizer.warmUp(profile: settings.asrProfile)
        for round in 1...repeats {
            let audio = ReplayAudio()
            let repository = InMemoryRepository()
            let metrics = RecordingMetrics()
            let inserter = RecordingInserter()
            let service = CleanupService(cleaner: cleaner,
                config: CleanupConfig(hardTokenCap: 800,
                                      interactiveDeadlineMs: settings.interactiveDeadlineMs,
                                      backgroundDeadlineMs: settings.backgroundDeadlineMs,
                                      workers: settings.cleanupWorkers),
                metrics: metrics)
            let pipeline = TextPipelineBuilder.make(settings: settings,
                dependencies: TextPipelineDependencies(cleaner: service))
            let engine = SessionEngine(audio: audio, recognizer: recognizer, pipeline: pipeline,
                                       repository: repository, journals: FakeJournalStore(),
                                       inserter: inserter, settings: settings, metrics: metrics,
                                       streamingCleanupEnabled: args[2] != "old")
            let sessionID = try await engine.start()
            let clock = ContinuousClock()
            let start = clock.now
            for offset in stride(from: 0, to: samples.count, by: 1_600) {
                let end = min(samples.count, offset + 1_600)
                try await clock.sleep(until: start.advanced(by: .seconds(Double(end) / 16_000 / pace)))
                await audio.send(Array(samples[offset..<end]), offset: offset)
            }
            let before = try await repository.segments(session: sessionID)
            let cleanedBefore = before.filter { $0.cleanupState == .cleaned }.count
            let outcome = await engine.stop()
            let after = try await repository.segments(session: sessionID)
            let ms = metrics.records.last { $0.0 == "session.stop.to_insert_return.ms" }?.1 ?? -1
            let cleanup = metrics.records.last { $0.0 == "session.stop.cleanup_wait.ms" }?.1 ?? -1
            let rawWords = after.map(\.rawText).joined(separator: " ").split(whereSeparator: \.isWhitespace).count
            let pending = after.filter { $0.cleanupState != .cleaned }
            let tailWords = after.dropFirst(before.count).map(\.rawText).joined(separator: " ")
                .split(whereSeparator: \.isWhitespace).count
            let reused = metrics.events.filter { $0 == "session.cleanup.prefix_reused" }.count
            let accepted = metrics.events.filter { $0 == "cleanup.chunk.accepted" }.count
            print("run=\(round) audio=\(Double(samples.count) / 16_000) pace=\(pace) lanes=\(await runtime.activeSessionCount) stopMs=\(ms) cleanupMs=\(cleanup) words=\(rawWords) before=\(before.count) cleanedBefore=\(cleanedBefore) accepted=\(accepted) reused=\(reused) tailWords=\(tailWords) segments=\(after.count) unfinished=\(pending.count) outcome=\(String(describing: outcome?.insertion))")
            let raw = after.map(\.rawText).joined(separator: " ")
            try raw.write(toFile: ".proof/stream/\(args[2])-\(sessions)-\(Int(Double(samples.count) / 16_000))-\(round).txt", atomically: true, encoding: .utf8)
            guard ms >= 0, rawWords > 0, outcome?.insertion == .pasted else {
                throw CocoaError(.fileReadUnknown)
            }
        }
    }
}
