@preconcurrency import CoreML
import FluidAudio
import Foundation

/// Per-stream speech/silence classification. The return value is the number of
/// samples in `samples` that were speech, which lets the stream track pauses in
/// audio time rather than wall time.
public protocol VoiceActivityClassifying: Sendable {
    func classify(_ samples: [Float]) async -> Int
}

public typealias VoiceActivityFactory = @Sendable () async -> any VoiceActivityClassifying

/// Deterministic fallback used when the Silero artifact is not installed.
/// It is intentionally simple: a fixed RMS gate. The segmenter still owns the
/// 600 ms pause rule, so a noisy room only shifts when a segment ends.
public struct EnergyVoiceActivity: VoiceActivityClassifying {
    public let threshold: Float

    public init(threshold: Float = 0.0025) {
        self.threshold = threshold
    }

    public func classify(_ samples: [Float]) async -> Int {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        return rms >= threshold ? samples.count : 0
    }
}

/// Silero VAD behind a per-stream state machine. FluidAudio requires exactly
/// 4096-sample chunks, so partial chunks are carried over between feeds.
public actor SileroVoiceActivity: VoiceActivityClassifying {
    private let manager: VadManager
    private let segmentation: VadSegmentationConfig
    private var state: VadStreamState
    private var pending: [Float] = []

    public init(manager: VadManager,
                segmentation: VadSegmentationConfig = VadSegmentationConfig(minSilenceDuration: 0.6)) {
        self.manager = manager
        self.segmentation = segmentation
        self.state = .initial()
    }

    public func classify(_ samples: [Float]) async -> Int {
        guard !samples.isEmpty else { return 0 }
        pending.append(contentsOf: samples)
        var speechSamples = 0
        while pending.count >= VadManager.chunkSize {
            let chunk = Array(pending.prefix(VadManager.chunkSize))
            pending.removeFirst(VadManager.chunkSize)
            do {
                let result = try await manager.processStreamingChunk(
                    chunk, state: state, config: segmentation)
                state = result.state
                if result.probability >= 0.5 { speechSamples += chunk.count }
            } catch {
                // A failed VAD chunk is treated as silence; the recognizer keeps
                // running and the 120 s hard cap still bounds the segment.
                state = .initial()
            }
        }
        return speechSamples
    }
}

enum SileroVoiceActivityLoader {
    static func makeManager(modelURL: URL) throws -> VadManager {
        let configuration = MLModelConfiguration()
        // One ML runtime for the whole recording: the VAD follows the same locked
        // compute-units policy as the recognizer, so the per-chunk encoder and VAD
        // calls never cross device runtimes.
        configuration.computeUnits = FluidAudioEngineLoader.computeUnits()
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        return VadManager(config: .default, vadModel: model)
    }
}
