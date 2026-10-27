@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import os
import SuperflowKernel
import SuperflowPorts

/// One recognition stream. It owns segment rotation (30 s + 600 ms pause, or a
/// 120 s hard cap), the 8 s stall watchdog, and the bounded replay buffer.
///
/// Every call into FluidAudio is raced against a wall-clock deadline. A model
/// call that never returns is abandoned and the stream rebuilds a recognizer
/// from the replay buffer; the journal remains the durable source of truth.
public actor FluidAudioRecognitionStream: RecognitionStream {
    public nonisolated let events: AsyncStream<RecognitionEvent>

    struct Deadlines: Sendable {
        var push: Duration
        var finish: Duration
        var reset: Duration
        var retire: Duration

        init(push: Duration = .seconds(8), finish: Duration = .seconds(5),
             reset: Duration = .seconds(3), retire: Duration = .seconds(2)) {
            self.push = push
            self.finish = finish
            self.reset = reset
            self.retire = retire
        }
    }

    private let continuation: AsyncStream<RecognitionEvent>.Continuation
    private var manager: any StreamingAsrManager
    private let profileID: String
    private let source: AudioSourceKind
    private let modelDirectory: URL
    private let engineFactory: FluidAudioEngineFactory
    private let voiceActivity: any VoiceActivityClassifying
    private let returnEngine: @Sendable (any StreamingAsrManager) async -> Void
    private let deadlines: Deadlines

    private let tokenSignal = FlagSignal()
    private let endpointSignal = FlagSignal()
    private let callbacks = CallbackGeneration()
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
    /// False while the current manager is stalled or its replacement failed.
    /// Audio keeps flowing to the journal, but it is not fed to a dead model.
    private var managerIsHealthy = true

    init(profileID: String, source: AudioSourceKind, manager: any StreamingAsrManager,
         modelDirectory: URL, engineFactory: @escaping FluidAudioEngineFactory,
         voiceActivity: any VoiceActivityClassifying,
         deadlines: Deadlines = Deadlines(),
         returnEngine: @escaping @Sendable (any StreamingAsrManager) async -> Void) {
        self.profileID = profileID
        self.source = source
        self.manager = manager
        self.modelDirectory = modelDirectory
        self.engineFactory = engineFactory
        self.voiceActivity = voiceActivity
        self.deadlines = deadlines
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

        await push(chunk.samples)

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
        if let text = await finishText(), !text.isEmpty {
            continuation.yield(.committed(RawSegment(text: text, startSample: segmentStartSample,
                                                     endSample: end, source: source)))
        }

        // Mute every recognizer before it is reset or returned to the pool.
        callbacks.advance()
        await resetManagerIfHealthy()
        continuation.finish()
        // A stalled manager is abandoned, never pooled.
        if managerIsHealthy { await returnEngine(manager) }
    }

    // MARK: - Model calls

    /// Appends audio and runs inference behind one deadline. A timeout leaves the
    /// manager unusable; the segment is replayed into a fresh one.
    private func push(_ samples: [Float]) async {
        guard managerIsHealthy else { return }
        do {
            try await withDeadline(deadlines.push, label: "ASR push") { [manager] in
                try await manager.appendAudio(FluidAudioBuffer.make(samples))
                try await manager.processBufferedAudio()
            }
        } catch {
            managerIsHealthy = false
            continuation.yield(.failure("Recognizer stalled while processing audio (\(error.localizedDescription))"))
            _ = await rebuild(reason: "push")
        }
    }

    private func finishText() async -> String? {
        if !managerIsHealthy {
            let recovered = await rebuild(reason: "finish")
            guard recovered else { return nil }
        }
        do {
            return try await finishOnce()
        } catch {
            managerIsHealthy = false
            continuation.yield(.failure("Recognizer stalled while finishing (\(error.localizedDescription))"))
            guard await rebuild(reason: "finish") else { return nil }
            do {
                return try await finishOnce()
            } catch {
                managerIsHealthy = false
                continuation.yield(.failure("Recognizer could not finish (\(error.localizedDescription))"))
                return nil
            }
        }
    }

    private func finishOnce() async throws -> String {
        let text = try await withDeadline(deadlines.finish, label: "ASR finish") { [manager] in
            try await manager.finish()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetManagerIfHealthy() async {
        guard managerIsHealthy else {
            // A new segment starts with an empty replay buffer, so swapping in a
            // fresh recognizer here is cheap and restores live transcription.
            _ = await rebuild(reason: "reset")
            return
        }
        do {
            try await withDeadline(deadlines.reset, label: "ASR reset") { [manager] in
                try await manager.reset()
            }
        } catch {
            managerIsHealthy = false
            _ = await rebuild(reason: "reset")
        }
    }

    // MARK: - Segment rotation

    private func commit(reason: CommitReason) async {
        let end = await commitEndSample(reason: reason)
        if let text = await finishText(), !text.isEmpty {
            continuation.yield(.committed(RawSegment(text: text, startSample: segmentStartSample,
                                                     endSample: end, source: source)))
        }
        continuation.yield(.endpoint(end))
        _ = tokenSignal.take()
        _ = endpointSignal.take()
        resetSegment(after: max(end, lastFeedEndSample))
        await resetManagerIfHealthy()
    }

    private func commitEndSample(reason: CommitReason) async -> Int64 {
        var candidate = lastFeedEndSample
        if reason == .pause, lastSpeechEndSample > segmentStartSample {
            candidate = lastSpeechEndSample
        }
        if reason == .nativeEndpoint, managerIsHealthy,
           let eou = manager as? StreamingEouAsrManager,
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
        _ = await rebuild(reason: "no transcript while speech was present")
    }

    /// Builds a fresh recognizer and replays the uncommitted segment into it.
    /// The previous manager is retired behind a deadline: if it is wedged inside
    /// Core ML, it is abandoned instead of blocking the audio path forever.
    private func rebuild(reason: String) async -> Bool {
        guard recoveries < FluidAudioSegmentPolicy.maximumRecoveriesPerSegment else {
            samplesSinceToken = 0
            return false
        }
        recoveries += 1
        let previous = manager
        managerIsHealthy = false

        do {
            let rebuilt = try await engineFactory(profileID, modelDirectory)
            await installCallbacks(on: rebuilt)
            let audio = replay.samples
            var start = 0
            while start < audio.count {
                let end = min(start + sampleRate, audio.count)
                let block = Array(audio[start..<end])
                try await withDeadline(deadlines.push, label: "ASR replay") { [rebuilt] in
                    try await rebuilt.appendAudio(FluidAudioBuffer.make(block))
                    try await rebuilt.processBufferedAudio()
                }
                start = end
            }
            manager = rebuilt
            managerIsHealthy = true
            samplesSinceToken = 0
            _ = tokenSignal.take()
            _ = endpointSignal.take()
            await retire(previous, reason: reason)
            return true
        } catch {
            managerIsHealthy = false
            continuation.yield(.failure("Could not rebuild the recognizer: \(error.localizedDescription)"))
            samplesSinceToken = 0
            return false
        }
    }

    private func retire(_ manager: any StreamingAsrManager, reason: String) async {
        do {
            try await withDeadline(deadlines.retire, label: "ASR retire (\(reason))") { [manager] in
                await manager.setPartialTranscriptCallback { _ in }
                if let eou = manager as? StreamingEouAsrManager {
                    await eou.setEouCallback { _ in }
                }
                await manager.cleanup()
            }
        } catch {
            // Abandoned. Core ML cannot be cancelled from this process, so the
            // model stays wedged until it returns on its own or we are killed.
        }
    }

    private func installCallbacks(on manager: any StreamingAsrManager) async {
        let generation = callbacks.advance()
        let generations = callbacks
        let tokenSignal = tokenSignal
        let endpointSignal = endpointSignal
        let continuation = continuation
        await manager.setPartialTranscriptCallback { text in
            guard generations.isCurrent(generation) else { return }
            tokenSignal.mark()
            continuation.yield(.partial(text))
        }
        if let eou = manager as? StreamingEouAsrManager {
            await eou.setEouCallback { _ in
                guard generations.isCurrent(generation) else { return }
                endpointSignal.mark()
            }
        }
    }
}
