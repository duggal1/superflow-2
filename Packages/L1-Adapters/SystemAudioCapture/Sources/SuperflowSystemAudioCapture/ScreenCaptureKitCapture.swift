import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import SuperflowKernel
import SuperflowPorts

/// ScreenCaptureKit audio-only fallback. Needs one Screen Recording grant and
/// captures the same process mix the Core Audio tap exposes.
final class ScreenCaptureKitCapture: NSObject, SystemAudioBackend, SCStreamOutput,
    SCStreamDelegate, @unchecked Sendable {
    let kind: SystemAudioBackendKind = .screenCaptureKit

    private let lock = NSLock()
    private var stream: SCStream?
    private var sampleContinuation: AsyncStream<AudioChunk>.Continuation?
    private var eventContinuation: AsyncStream<AudioEvent>.Continuation?
    private var converter: AudioSampleConverter?
    private var cursor: Int64 = 0
    private var running = false
    private let queue = DispatchQueue(label: "com.superflow.system-audio.sck", qos: .userInitiated)

    func start() async throws -> AudioStreams {
        let alreadyRunning = lock.withLock { running }
        guard !alreadyRunning else {
            throw SuperflowError.invalidState("system audio already running")
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw SystemAudioCaptureFailure.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw SystemAudioCaptureFailure.permissionDenied
        }
        guard let display = content.displays.first else {
            throw SystemAudioCaptureFailure.startFailed(
                "No display is available for ScreenCaptureKit system audio.")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = sampleRate
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true
        configuration.showsCursor = false
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)

        let (samples, sampleContinuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(600))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16))

        lock.withLock {
            converter = AudioSampleConverter(inputRate: Double(sampleRate))
            cursor = 0
            self.sampleContinuation = sampleContinuation
            self.eventContinuation = eventContinuation
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            sampleContinuation.finish()
            eventContinuation.finish()
            lock.withLock {
                self.sampleContinuation = nil
                self.eventContinuation = nil
                self.converter = nil
            }
            throw SystemAudioCaptureFailure.startFailed(error.localizedDescription)
        }

        lock.withLock {
            self.stream = stream
            running = true
        }
        return AudioStreams(samples: samples, events: events)
    }

    func stop() async {
        let state = lock.withLock { () -> (SCStream?, AsyncStream<AudioChunk>.Continuation?,
                                            AsyncStream<AudioEvent>.Continuation?) in
            let value = (stream, sampleContinuation, eventContinuation)
            stream = nil
            sampleContinuation = nil
            eventContinuation = nil
            converter = nil
            running = false
            return value
        }
        if let stream = state.0 {
            try? await stream.stopCapture()
            // `removeStreamOutput` is throwing on current SDKs. A failed removal
            // only means the stream was already torn down; shutdown continues.
            try? stream.removeStreamOutput(self, type: .audio)
        }
        state.1?.finish()
        state.2?.yield(.stopped)
        state.2?.finish()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        lock.withLock {
            guard running, let continuation = sampleContinuation, var converter else { return }
            let samples = converter.convert(sampleBuffer)
            self.converter = converter
            guard !samples.isEmpty else { return }
            let value = AudioChunk(samples: samples, startSample: cursor, source: .system)
            cursor += Int64(samples.count)
            continuation.yield(value)
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let continuation = lock.withLock { () -> AsyncStream<AudioEvent>.Continuation? in
            guard running else { return nil }
            running = false
            let value = eventContinuation
            eventContinuation = nil
            sampleContinuation?.finish()
            sampleContinuation = nil
            self.stream = nil
            return value
        }
        continuation?.yield(.failed(error.localizedDescription))
        continuation?.finish()
    }
}
