import AVFoundation
import Foundation
import SuperflowKernel
import SuperflowPorts

/// AVAudioEngine microphone capture converted to 16 kHz mono Float32.
///
/// The sample-rate conversion happens inside the audio graph: the input node is
/// connected to a mixer at the hardware format and the mixer to the main mixer
/// at 16 kHz mono. That avoids the aliasing and per-buffer allocation of a
/// hand-written linear resampler on the realtime thread.
public final class MicrophoneCapture: AudioSource, @unchecked Sendable {
    public let kind: AudioSourceKind = .mic
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var mixer: AVAudioMixerNode?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var eventContinuation: AsyncStream<AudioEvent>.Continuation?
    private var consumer: Task<Void, Never>?
    private var running = false
    private var stopping = false
    private var observer: NSObjectProtocol?
    private let ring = AudioRingBuffer()

    /// Samples the audio thread had to drop because the consumer fell behind.
    public var droppedSamples: Int { ring.droppedSamples }

    public init() {}

    public func start() async throws -> AudioStreams {
        if lock.withLock({ running || stopping }) { throw SuperflowError.invalidState("microphone already running") }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw SuperflowError.permissionDenied(Permission.microphone.label) }

        let (samples, sampleContinuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(600))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let (engine, mixer) = try makeEngine()

        lock.withLock {
            self.engine = engine
            self.mixer = mixer
            self.continuation = sampleContinuation
            self.eventContinuation = eventContinuation
            self.running = true
        }
        let consumer = Task { [weak self] in
            guard let self else { return }
            await self.drain(into: sampleContinuation)
        }
        lock.withLock { self.consumer = consumer }
        observeRouteChanges(for: engine)
        return AudioStreams(samples: samples, events: events)
    }

    public func stop() async {
        let (shouldStop, engineToStop, mixerToStop) = lock.withLock { () -> (Bool, AVAudioEngine?, AVAudioMixerNode?) in
            guard running, !stopping else { return (false, nil, nil) }
            stopping = true
            return (true, engine, mixer)
        }
        guard shouldStop else { return }
        mixerToStop?.removeTap(onBus: 0)
        engineToStop?.stop()

        let state = lock.withLock { () -> (AsyncStream<AudioChunk>.Continuation?,
                                            AsyncStream<AudioEvent>.Continuation?, Task<Void, Never>?,
                                            NSObjectProtocol?) in
            let value = (continuation, eventContinuation, consumer, observer)
            engine = nil
            mixer = nil
            continuation = nil
            eventContinuation = nil
            consumer = nil
            observer = nil
            running = false
            return value
        }
        if let consumer = state.2 { await consumer.value }
        lock.withLock { stopping = false }
        state.0?.finish()
        state.1?.yield(.stopped)
        state.1?.finish()
        if let observer = state.3 {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func drain(into continuation: AsyncStream<AudioChunk>.Continuation) async {
        var scratch: [Float] = Array(repeating: 0, count: 1_600)
        var cursor: Int64 = 0
        while true {
            let count = ring.read(into: &scratch, max: 1_600)
            if count == 0 {
                if !lock.withLock({ running }) { break }
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }
            let samples = Array(scratch[0..<count])
            continuation.yield(AudioChunk(samples: samples, startSample: cursor, source: .mic))
            cursor += Int64(count)
        }
    }

    private func makeEngine() throws -> (AVAudioEngine, AVAudioMixerNode) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else {
            throw SuperflowError.audioFailure("no microphone input format")
        }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(sampleRate),
                                         channels: 1, interleaved: false) else {
            throw SuperflowError.audioFailure("could not create a 16 kHz mono format")
        }

        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(input, to: mixer, format: hardware)
        engine.connect(mixer, to: engine.mainMixerNode, format: target)
        // Keep the graph pulled while monitoring nothing: dictation must not echo.
        engine.mainMixerNode.outputVolume = 0

        let ring = self.ring
        mixer.installTap(onBus: 0, bufferSize: 1_024, format: target) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            _ = ring.write(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        engine.prepare()
        do {
            try engine.start()
            return (engine, mixer)
        } catch {
            mixer.removeTap(onBus: 0)
            throw SuperflowError.audioFailure(error.localizedDescription)
        }
    }

    private func observeRouteChanges(for engine: AVAudioEngine) {
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            Task.detached { self.rebuildAfterRouteChange() }
        }
        let installed = lock.withLock { () -> Bool in
            guard running, self.engine === engine else { return false }
            self.observer = observer
            return true
        }
        if !installed { NotificationCenter.default.removeObserver(observer) }
    }

    private func rebuildAfterRouteChange() {
        let state = lock.withLock { () -> (AVAudioEngine, AVAudioMixerNode?, NSObjectProtocol?,
                                            AsyncStream<AudioEvent>.Continuation?)? in
            guard running, !stopping, let engine else { return nil }
            self.engine = nil
            let mixer = self.mixer
            self.mixer = nil
            let observer = self.observer
            self.observer = nil
            return (engine, mixer, observer, eventContinuation)
        }
        guard let (oldEngine, oldMixer, oldObserver, events) = state else { return }
        if let oldObserver { NotificationCenter.default.removeObserver(oldObserver) }
        oldMixer?.removeTap(onBus: 0)
        oldEngine.stop()
        events?.yield(.routeChanged)

        do {
            let (replacement, replacementMixer) = try makeEngine()
            let installed = lock.withLock { () -> Bool in
                guard running, !stopping else { return false }
                engine = replacement
                mixer = replacementMixer
                return true
            }
            guard installed else {
                replacementMixer.removeTap(onBus: 0)
                replacement.stop()
                return
            }
            observeRouteChanges(for: replacement)
        } catch {
            events?.yield(.failed(error.localizedDescription))
        }
    }
}
