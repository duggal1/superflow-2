import AVFoundation
import Foundation
import Synchronization

/// Single-producer/single-consumer ring. The audio tap writes; a consumer task reads.
/// No locks, no allocation and no Swift concurrency on the audio thread.
final class AudioRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)

    init(capacity: Int = 48_000) {
        self.capacity = max(1, capacity)
        storage = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
        storage.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    @discardableResult
    func write(_ source: UnsafeBufferPointer<Float>) -> Int {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let free = capacity - (write - read)
        let count = min(source.count, max(0, free))
        guard count > 0 else { return 0 }
        for i in 0..<count {
            storage[(write + i) % capacity] = source[i]
        }
        writeIndex.store(write + count, ordering: .releasing)
        return count
    }

    @discardableResult
    func read(into destination: inout [Float], max maxCount: Int) -> Int {
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        let available = write - read
        let count = min(maxCount, Swift.max(0, available))
        guard count > 0 else { return 0 }
        if destination.count < count { destination.append(contentsOf: repeatElement(0, count: count - destination.count)) }
        for i in 0..<count {
            destination[i] = storage[(read + i) % capacity]
        }
        readIndex.store(read + count, ordering: .releasing)
        return count
    }

    var available: Int {
        writeIndex.load(ordering: .acquiring) - readIndex.load(ordering: .acquiring)
    }
}

/// Linear resampler from the device rate to 16 kHz. Owned by the audio thread.
final class AudioResampler: @unchecked Sendable {
    private let ratio: Double
    private var phase: Double = 0
    private var scratch: [Float] = []

    init(inputRate: Double, outputRate: Double = 16_000) {
        ratio = max(0.0001, inputRate / outputRate)
        scratch.reserveCapacity(8_192)
    }

    func process(_ buffer: AVAudioPCMBuffer, into ring: AudioRingBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 1 else { return }
        let channels = Int(buffer.format.channelCount)
        scratch.removeAll(keepingCapacity: true)
        var position = phase
        while position < Double(frames - 1) {
            let index = Int(position)
            let fraction = Float(position - Double(index))
            var sample: Float = 0
            for channel in 0..<channels {
                let lane = data[channel]
                sample += lane[index] * (1 - fraction) + lane[index + 1] * fraction
            }
            scratch.append(sample / Float(max(1, channels)))
            position += ratio
        }
        phase = position - Double(frames - 1)
        _ = scratch.withUnsafeBufferPointer { ring.write($0) }
    }
}
