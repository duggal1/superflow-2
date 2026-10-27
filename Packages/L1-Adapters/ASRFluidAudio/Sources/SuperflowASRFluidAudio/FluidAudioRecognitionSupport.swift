@preconcurrency import AVFoundation
import Foundation
import os
import SuperflowKernel

/// Segment geometry, the watchdog's signal, the callback generation guard, the bounded replay
/// buffer and the input buffer builder: the pieces `FluidAudioRecognitionStream` uses but does not
/// own. Kept in their own file so both stay inside the repository's 400-line source limit.

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

/// Monotonic callback generation. A recognizer that was abandoned after a stall
/// may still invoke its callbacks later; those deliveries must be ignored rather
/// than corrupting the replacement recognizer's partial transcript state.
final class CallbackGeneration: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Int>(initialState: 0)

    @discardableResult
    func advance() -> Int {
        lock.withLock { value in
            value += 1
            return value
        }
    }

    func isCurrent(_ generation: Int) -> Bool {
        lock.withLock { $0 == generation }
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

enum CommitReason {
    case nativeEndpoint
    case pause
    case hardCap
}
