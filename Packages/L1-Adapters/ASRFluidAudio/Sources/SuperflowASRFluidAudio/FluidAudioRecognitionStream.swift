@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import SuperflowKernel
import SuperflowPorts

enum FluidAudioSegmentPolicy {
    static let minimumSegmentSamples = 30 * sampleRate
    static let pauseSamples = 600 * sampleRate / 1000
    static let hardCapSamples = 120 * sampleRate
    static let watchdogSamples = 8 * sampleRate
    static let replayLimitSamples = 125 * sampleRate
    static let maximumRecoveriesPerSegment = 2
}

/// Lock-backed one-shot flag used by FluidAudio callbacks, which are invoked
/// outside the stream actor and must never block audio processing.
final class FlagSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() { lock.withLock { marked = true } }

    func take() -> Bool {
        lock.withLock {
            defer { marked = false }
            return marked
        }
    }
}

/// Bounded copy of the current, uncommitted segment. It exists so the watchdog
/// can replay after a recognizer rebuild without retaining the whole recording.
struct ReplayBuffer {
    private(set) var samples: [Float] = []
    let limit: Int

    init(limit: Int = FluidAudioSegmentPolicy.replayLimitSamples) {
        self.limit = limit
    }

    mutating func append(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
        let overflow = samples.count - limit
        if overflow > 0 { samples.removeFirst(overflow) }
    }

    mutating func removeAll() { samples.removeAll(keepingCapacity: true) }
}

enum FluidAudioBuffer {
    static func make(_ samples: [Float], rate: Int = sampleRate) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(rate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?.pointee else {
            throw SuperflowError.audioFailure("Could not allocate a FluidAudio input buffer.")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices { channel[index] = samples[index] }
        return buffer
    }
}

private enum CommitReason {
    case nativeEndpoint
    case pause
    case hardCap
}

/// One recognition stream. It owns segment rotation (30 s + 600 ms pause, or a
/// 120 s hard cap), the 8 s stall watchdog, and the bounded replay buffer.
public actor FluidAudioRecognitionStream: RecognitionStream {
    public nonisolated let events: AsyncStream<RecognitionEvent>

    private let continuation: AsyncStream<RecognitionEvent>.Continuation
    private var manager: any StreamingAsrManager
    private let profileID: String
    private let source: AudioSourceKind
    private let modelDirectory: URL
    private let engineFactory: FluidAudioEngineFactory
    private let voiceActivity: any VoiceActivityClassifying
    private let returnEngine: @Sendable (any StreamingAsrManager) async -> Void

    private let tokenSignal = FlagSignal()
    private let endpointSignal = FlagSignal()
    private var replay = ReplayBuffer()
    private var segmentStartSample: Int64 = 0
    private var lastFeedEndSample: Int64 = 0
    private var lastSpeechEndSample: Int64 = 0
    private var segmentSamples = 0
    private var silenceSamples = 0
    private var samplesSinceToken = 0
    private var heardSpeech = false
    private var recoveries = 0
    private var isFinished = false

    init(profileID: String, source: AudioSourceKind, manager: any StreamingAsrManager,
         modelDirectory: URL, engineFactory: @escaping FluidAudioEngineFactory,
         voiceActivity: any VoiceActivityClassifying,
         returnEngine: @escaping @Sendable (any StreamingAsrManager) async -> Void) {
        self.profileID = profileID
        self.source = source
        self.manager = manager
        self.modelDirectory = modelDirectory
        self.engineFactory = engineFactory
        self.voiceActivity = voiceActivity
        self.returnEngine = returnEngine
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(128))
    }

    func configure() async {
        await installCallbacks(on: manager)
    }

    public func feed(_ chunk: AudioChunk) async {
        guard !isFinished, !chunk.samples.isEmpty else { return }
        guard chunk.source == source else {
            continuation.yield(.failure("Audio source did not match the recognition stream."))
            return
        }

        lastFeedEndSample = chunk.endSample
        replay.append(chunk.samples)
        segmentSamples += chunk.samples.count
        do {
            try await manager.appendAudio(FluidAudioBuffer.make(chunk.samples))
            try await manager.processBufferedAudio()
        } catch {
            continuation.yield(.failure(error.localizedDescription))
            return
        }

        let speechSamples = await voiceActivity.classify(chunk.samples)
        if speechSamples > 0 {
            heardSpeech = true
            silenceSamples = 0
            lastSpeechEndSample = chunk.endSample
        } else {
            silenceSamples += chunk.samples.count
        }

        if tokenSignal.take() {
            samplesSinceToken = 0
            recoveries = 0
        } else if heardSpeech {
            samplesSinceToken += chunk.samples.count
        }

        if endpointSignal.take() {
            await commit(reason: .nativeEndpoint)
            return
        }
        if segmentSamples >= FluidAudioSegmentPolicy.hardCapSamples {
            await commit(reason: .hardCap)
            return
        }
        if segmentSamples >= FluidAudioSegmentPolicy.minimumSegmentSamples,
           silenceSamples >= FluidAudioSegmentPolicy.pauseSamples {
            await commit(reason: .pause)
            return
        }
        if heardSpeech && samplesSinceToken >= FluidAudioSegmentPolicy.watchdogSamples {
            await recoverFromStall()
        }
    }

    public func finish() async {
        guard !isFinished else { return }
        isFinished = true
        let end = max(segmentStartSample, lastFeedEndSample)
        do {
            let text = try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                continuation.yield(.committed(RawSegment(text: text, startSample: segmentStartSample,
                                                         endSample: end, source: source)))
            }
        } catch {
            continuation.yield(.failure(error.localizedDescription))
        }

        await manager.setPartialTranscriptCallback { _ in }
        if let eou = manager as? StreamingEouAsrManager {
            await eou.setEouCallback { _ in }
        }
        try? await manager.reset()
        continuation.finish()
        await returnEngine(manager)
    }

    // MARK: - Segment rotation

    private func commit(reason: CommitReason) async {
        let end = await commitEndSample(reason: reason)
        do {
            let text = try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                continuation.yield(.committed(RawSegment(text: text, startSample: segmentStartSample,
                                                         endSample: end, source: source)))
            }
        } catch {
            continuation.yield(.failure(error.localizedDescription))
        }
        continuation.yield(.endpoint(end))
        try? await manager.reset()
        _ = tokenSignal.take()
        _ = endpointSignal.take()
        resetSegment(after: max(end, lastFeedEndSample))
    }

    private func commitEndSample(reason: CommitReason) async -> Int64 {
        var candidate = lastFeedEndSample
        if reason == .pause, lastSpeechEndSample > segmentStartSample {
            candidate = lastSpeechEndSample
        }
        if reason == .nativeEndpoint, let eou = manager as? StreamingEouAsrManager,
           let milliseconds = await eou.getEouTimestampsMs().last {
            let estimated = segmentStartSample + Int64(milliseconds) * Int64(sampleRate) / 1000
            candidate = min(candidate, max(segmentStartSample, estimated))
        }
        return min(max(candidate, segmentStartSample), max(lastFeedEndSample, segmentStartSample))
    }

    private func resetSegment(after end: Int64) {
        segmentStartSample = end
        lastSpeechEndSample = end
        segmentSamples = 0
        silenceSamples = 0
        samplesSinceToken = 0
        heardSpeech = false
        recoveries = 0
        replay.removeAll()
    }

    // MARK: - Watchdog

    private func recoverFromStall() async {
        guard recoveries < FluidAudioSegmentPolicy.maximumRecoveriesPerSegment else {
            samplesSinceToken = 0
            return
        }
        recoveries += 1
        let old = manager
        do {
            let rebuilt = try await engineFactory(profileID, modelDirectory)
            await installCallbacks(on: rebuilt)
            let audio = replay.samples
            var start = 0
            while start < audio.count {
                let end = min(start + sampleRate, audio.count)
                try await rebuilt.appendAudio(FluidAudioBuffer.make(Array(audio[start..<end])))
                try await rebuilt.processBufferedAudio()
                start = end
            }
            await old.setPartialTranscriptCallback { _ in }
            if let eou = old as? StreamingEouAsrManager {
                await eou.setEouCallback { _ in }
            }
            await old.cleanup()
            manager = rebuilt
            samplesSinceToken = 0
            _ = tokenSignal.take()
        } catch {
            continuation.yield(.failure("Could not rebuild the recognizer: \(error.localizedDescription)"))
            samplesSinceToken = 0
        }
    }

    private func installCallbacks(on manager: any StreamingAsrManager) async {
        let tokenSignal = tokenSignal
        let endpointSignal = endpointSignal
        let continuation = continuation
        await manager.setPartialTranscriptCallback { text in
            tokenSignal.mark()
            continuation.yield(.partial(text))
        }
        if let eou = manager as? StreamingEouAsrManager {
            await eou.setEouCallback { _ in endpointSignal.mark() }
        }
    }
}
