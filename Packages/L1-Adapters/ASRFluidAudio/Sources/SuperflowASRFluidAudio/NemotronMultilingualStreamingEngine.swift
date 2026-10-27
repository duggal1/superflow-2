@preconcurrency import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation
import SuperflowKernel

/// Adapts FluidAudio's multilingual Nemotron 3.5 manager to the common
/// `StreamingAsrManager` protocol. FluidAudio owns the cache-aware pipeline;
/// this wrapper only bridges the append-and-drain contract used by
/// `FluidAudioRecognitionStream`.
actor NemotronMultilingualStreamingEngine: StreamingAsrManager {
    nonisolated let displayName = "Nemotron 3.5 ASR Streaming 0.6B"

    private let manager: StreamingNemotronMultilingualAsrManager
    private var pendingSamples: [Float] = []
    private var partialCallback: (@Sendable (String) -> Void)?

    init(configuration: MLModelConfiguration) {
        manager = StreamingNemotronMultilingualAsrManager(configuration: configuration)
    }

    /// The app loads only from its already-downloaded cache; it never triggers
    /// a network download during recording.
    func loadModels() async throws {
        throw SuperflowError.modelUnavailable(
            "Nemotron 3.5 must be loaded from the local FluidAudio model cache.")
    }

    func loadModels(from directory: URL) async throws {
        try await manager.loadModels(from: directory)
        await installPartialCallback()
    }

    func appendAudio(_ buffer: AVAudioPCMBuffer) throws {
        guard Int(buffer.format.sampleRate) == sampleRate,
              buffer.format.channelCount == 1,
              let channel = buffer.floatChannelData?[0] else {
            throw SuperflowError.audioFailure(
                "Nemotron 3.5 expects 16 kHz mono Float32 audio.")
        }
        pendingSamples.append(
            contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func processBufferedAudio() async throws {
        await installPartialCallback()
        guard !pendingSamples.isEmpty else { return }
        let samples = pendingSamples
        pendingSamples.removeAll(keepingCapacity: true)
        _ = try await manager.process(samples: samples)
    }

    func finish() async throws -> String {
        defer { pendingSamples.removeAll(keepingCapacity: true) }
        return try await manager.finish()
    }

    func reset() async throws {
        pendingSamples.removeAll(keepingCapacity: true)
        await manager.reset()
    }

    func cleanup() async {
        pendingSamples.removeAll(keepingCapacity: true)
        await manager.cleanup()
    }

    func setPartialTranscriptCallback(_ callback: @escaping @Sendable (String) -> Void) {
        partialCallback = callback
    }

    func getPartialTranscript() -> String {
        ""
    }

    private func installPartialCallback() async {
        guard let partialCallback else { return }
        await manager.setPartialCallback(partialCallback)
    }
}
