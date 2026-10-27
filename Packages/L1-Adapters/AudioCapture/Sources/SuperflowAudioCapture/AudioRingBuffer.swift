import Foundation
import Synchronization

/// Single-producer/single-consumer ring. The audio tap writes; a consumer task reads.
/// No locks, no allocation and no Swift concurrency on the audio thread. Overflow
/// drops the newest samples and counts them so capture loss is observable.
final class AudioRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)

    /// ~32 s of 16 kHz audio: deep enough that a stalled recognizer or a slow
    /// rebuild cannot overrun the buffer while the journal keeps up.
    init(capacity: Int = 1 << 19) {
        self.capacity = max(1, capacity)
        storage = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
        storage.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    var droppedSamples: Int { dropped.load(ordering: .relaxed) }

    @discardableResult
    func write(_ source: UnsafeBufferPointer<Float>) -> Int {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let free = capacity - (write - read)
        let count = min(source.count, max(0, free))
        if count < source.count {
            _ = dropped.wrappingAdd(source.count - count, ordering: .relaxed)
        }
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
