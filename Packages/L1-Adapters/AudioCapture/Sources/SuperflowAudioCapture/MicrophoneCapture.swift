import AVFoundation
import Foundation
import SuperflowKernel
import SuperflowPorts

/// AVAudioEngine microphone capture converted to 16 kHz mono Float32.
public final class MicrophoneCapture: AudioSource, @unchecked Sendable {
    public let kind: AudioSourceKind = .mic
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var eventContinuation: AsyncStream<AudioEvent>.Continuation?
    private var consumer: Task<Void, Never>?
    private var running = false
    private var stopping = false
    private var observer: NSObjectProtocol?
    private let ring = AudioRingBuffer()

    public init() {}

    public func start() async throws -> AudioStreams {
        if lock.withLock({ running || stopping }) { throw SuperflowError.invalidState("microphone already running") }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw SuperflowError.permissionDenied(Permission.microphone.label) }

        let (samples, sampleContinuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(600))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let engine = try makeEngine()

        lock.withLock {
            self.engine = engine
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
        let (shouldStop, engineToStop) = lock.withLock { () -> (Bool, AVAudioEngine?) in
            guard running, !stopping else { return (false, nil) }
            stopping = true
            return (true, engine)
        }
        guard shouldStop else { return }
        engineToStop?.inputNode.removeTap(onBus: 0)
        engineToStop?.stop()

        let state = lock.withLock { () -> (AsyncStream<AudioChunk>.Continuation?,
                                            AsyncStream<AudioEvent>.Continuation?, Task<Void, Never>?,
                                            NSObjectProtocol?) in
            let value = (continuation, eventContinuation, consumer, observer)
            engine = nil
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

    private func makeEngine() throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SuperflowError.audioFailure("no microphone input format")
        }
        let resampler = AudioResampler(inputRate: format.sampleRate)
        let ring = self.ring
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            resampler.process(buffer, into: ring)
        }
        engine.prepare()
        do {
            try engine.start()
            return engine
        } catch {
            input.removeTap(onBus: 0)
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
        let state = lock.withLock { () -> (AVAudioEngine, NSObjectProtocol?, AsyncStream<AudioEvent>.Continuation?)? in
            guard running, !stopping, let engine else { return nil }
            self.engine = nil
            let observer = self.observer
            self.observer = nil
            return (engine, observer, eventContinuation)
        }
        guard let (oldEngine, oldObserver, events) = state else { return }
        if let oldObserver { NotificationCenter.default.removeObserver(oldObserver) }
        oldEngine.inputNode.removeTap(onBus: 0)
        oldEngine.stop()
        events?.yield(.routeChanged)

        do {
            let replacement = try makeEngine()
            let installed = lock.withLock { () -> Bool in
                guard running, !stopping else { return false }
                engine = replacement
                return true
            }
            guard installed else {
                replacement.inputNode.removeTap(onBus: 0)
                replacement.stop()
                return
            }
            observeRouteChanges(for: replacement)
        } catch {
            events?.yield(.failed(error.localizedDescription))
        }
    }
}
