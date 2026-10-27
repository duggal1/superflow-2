import AVFoundation
import Accelerate
import Foundation

// MARK: - Level source port

/// Linear RMS values, roughly 40 per second. The stream ends when the input is lost.
public protocol MicLevelSource: Sendable {
    var needsPermission: Bool { get }
    func start() throws -> AsyncStream<Float>
    func stop()
}

public extension MicLevelSource {
    var needsPermission: Bool { true }
}

public enum MicTestError: LocalizedError {
    case noInputDevice

    public var errorDescription: String? {
        "No microphone found. Plug one in or pick an input in System Settings."
    }
}

/// Real microphone through AVAudioEngine. Throwaway-grade: fine for a test, not
/// for recording. Only run it while no dictation session is recording.
public final class AVMicLevelSource: MicLevelSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    public init() {}

    public func start() throws -> AsyncStream<Float> {
        let (stream, continuation) = AsyncStream.makeStream(of: Float.self,
                                                            bufferingPolicy: .bufferingNewest(2))
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicTestError.noInputDevice
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))
            continuation.yield(rms)
        }

        // AirPods connect, default device changes, sample rate changes: end the
        // stream; the model says so.
        let token = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in continuation.finish() }
        lock.withLock { observer = token }

        continuation.onTermination = { [weak self] _ in self?.stop() }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw error
        }
        return stream
    }

    public func stop() {
        lock.withLock {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
