import AVFoundation
import CoreAudio
import Foundation
import SuperflowKernel
import SuperflowPorts

/// Explicit Core Audio input capture. Conversion and stream delivery run on this
/// actor; the IOProc only copies into a preallocated SPSC ring.
public actor MicrophoneCapture: AudioSource {
    public nonisolated let kind: AudioSourceKind = .mic
    private var stream: HALInputStream?
    private var samples: AsyncStream<AudioChunk>.Continuation?
    private var events: AsyncStream<AudioEvent>.Continuation?
    private var pump: Task<Void, Never>?
    private var running = false
    private var cursor: Int64 = 0
    private var lastProgress = ContinuousClock.now
    private var lastSignal = ContinuousClock.now
    private var silenceReported = false
    private var lastRouteCheck = ContinuousClock.now
    private var lastDropped = 0
    private var retryAfter = ContinuousClock.now

    public var droppedSamples: Int { stream?.ring.droppedSamples ?? lastDropped }

    public init() {}

    public func start() async throws -> AudioStreams {
        guard !running else { throw SuperflowError.invalidState("microphone already running") }
        running = true
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard running else { throw CancellationError() }
        guard granted else {
            running = false
            throw SuperflowError.permissionDenied(Permission.microphone.label)
        }
        do {
            let capture = try HALInputStream(device: InputDevice.resolve())
            try capture.start()
            stream = capture
        } catch { running = false; throw error }
        let (audio, sampleSink) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(600))
        let (notifications, eventSink) = AsyncStream<AudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        samples = sampleSink
        events = eventSink
        cursor = 0
        lastDropped = 0
        lastProgress = .now
        lastSignal = .now
        silenceReported = false
        lastRouteCheck = .now
        pump = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
        return AudioStreams(samples: audio, events: notifications)
    }

    public func stop() async {
        guard running else { return }
        running = false
        pump?.cancel()
        pump = nil
        stream?.stop()
        deliver()
        stream = nil
        samples?.finish()
        samples = nil
        events?.yield(.stopped)
        events?.finish()
        events = nil
    }

    private func deliver() {
        guard let stream else { return }
        do {
            let audio = try stream.drain()
            if !audio.isEmpty {
                lastProgress = .now
                if audio.contains(where: { $0 != 0 }) { lastSignal = .now; silenceReported = false }
                let result = samples?.yield(AudioChunk(samples: audio, startSample: cursor, source: .mic))
                if case .dropped = result { events?.yield(.failed("Microphone delivery overflowed; some audio was lost.")) }
                cursor += Int64(audio.count)
            }
            let dropped = stream.ring.droppedSamples
            if dropped > lastDropped { events?.yield(.failed("Microphone capture overflowed; some audio was lost.")) }
            lastDropped = dropped
        } catch { events?.yield(.failed(error.localizedDescription)) }
    }

    private func tick() {
        guard running else { return }
        deliver()
        let now = ContinuousClock.now
        if stream != nil, !silenceReported, now - lastSignal > .seconds(2) {
            silenceReported = true
            events?.yield(.failed("The microphone is sending silence. Check its mute switch and macOS input level."))
        }
        guard now - lastRouteCheck >= .milliseconds(250), now >= retryAfter else { return }
        lastRouteCheck = now
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            events?.yield(.permissionRevoked)
            stream?.stop()
            stream = nil
            return
        }
        do {
            let device = try InputDevice.resolve()
            let changed = stream?.device != device || InputDevice.format(device)?.mSampleRate != stream?.sampleRate
            let stalled = now - lastProgress > .milliseconds(1500)
            guard changed || stalled else { return }
            stream?.stop()
            deliver()
            stream = nil
            let replacement = try HALInputStream(device: device)
            try replacement.start()
            stream = replacement
            lastProgress = now
            lastSignal = now
            silenceReported = false
            lastDropped = 0
            events?.yield(.routeChanged)
        } catch {
            stream?.stop()
            stream = nil
            retryAfter = now + .seconds(1)
            events?.yield(.failed(error.localizedDescription))
        }
    }
}
