@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowASRFluidAudio

/// Creates the artifact tree `FluidAudioCatalog` expects. The files are empty:
/// tests replace the loader, so only existence matters.
func makeModelCache(profileID: String,
                    fileManager: FileManager = .default) throws -> URL {
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("asr-tests-\(UUID().uuidString)", isDirectory: true)
    guard let profile = FluidAudioCatalog.profile(for: profileID) else {
        throw SuperflowError.modelUnavailable("unknown profile")
    }
    let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: root)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    for artifact in profile.requiredArtifacts {
        let url = directory.appendingPathComponent(artifact)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Data().write(to: url)
    }
    return root
}

func makeVadArtifact(cacheRoot: URL, fileManager: FileManager = .default) throws {
    let url = FluidAudioCatalog.vadModelURL(cacheRoot: cacheRoot)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
    try Data().write(to: url)
}

actor FakeEngine: StreamingAsrManager {
    nonisolated let displayName = "Fake engine"
    private var text: String
    private var partialCallback: (@Sendable (String) -> Void)?
    private(set) var appendedSamples = 0
    private(set) var finishCount = 0
    private(set) var resetCount = 0
    private(set) var cleanupCount = 0
    var autoPartial = false

    init(text: String = "hello world") {
        self.text = text
    }

    func setText(_ value: String) { text = value }
    func setAutoPartial(_ value: Bool) { autoPartial = value }

    func loadModels() async throws {}

    func appendAudio(_ buffer: AVAudioPCMBuffer) throws {
        appendedSamples += Int(buffer.frameLength)
    }

    func processBufferedAudio() async throws {
        if autoPartial { partialCallback?("token") }
    }

    func finish() async throws -> String {
        finishCount += 1
        return text
    }

    func reset() async throws { resetCount += 1 }
    func cleanup() async { cleanupCount += 1 }

    func setPartialTranscriptCallback(_ callback: @escaping @Sendable (String) -> Void) {
        partialCallback = callback
    }

    func getPartialTranscript() -> String { text }
    func emitPartial(_ value: String) { partialCallback?(value) }
}

actor EngineSpy {
    private var engines: [FakeEngine] = []
    private var failure: Error?
    var count: Int { engines.count }

    func setFailure(_ error: Error?) { failure = error }

    func make() throws -> FakeEngine {
        if let failure { throw failure }
        let engine = FakeEngine()
        engines.append(engine)
        return engine
    }

    func engine(at index: Int) -> FakeEngine? {
        engines.indices.contains(index) ? engines[index] : nil
    }
}

actor FakeVoiceActivity: VoiceActivityClassifying {
    private var speech: Bool

    init(speech: Bool = true) {
        self.speech = speech
    }

    func setSpeech(_ value: Bool) { speech = value }

    func classify(_ samples: [Float]) async -> Int {
        speech ? samples.count : 0
    }
}

func chunk(seconds: Int, startSample: Int64, source: AudioSourceKind = .mic) -> AudioChunk {
    AudioChunk(samples: Array(repeating: 0.1, count: seconds * sampleRate),
               startSample: startSample, source: source)
}

/// Collects at most `count` events, giving up after `timeoutMs`.
func collectEvents(_ stream: any RecognitionStream, count: Int,
                   timeoutMs: Int = 2_000) async -> [RecognitionEvent] {
    await withTaskGroup(of: [RecognitionEvent].self) { group in
        group.addTask {
            var collected: [RecognitionEvent] = []
            for await event in stream.events {
                collected.append(event)
                if collected.count >= count { break }
            }
            return collected
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(timeoutMs))
            return []
        }
        let first = await group.next() ?? []
        group.cancelAll()
        return first
    }
}
