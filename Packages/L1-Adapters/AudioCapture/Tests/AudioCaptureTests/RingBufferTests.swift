import XCTest
@testable import SuperflowAudioCapture

final class RingBufferTests: XCTestCase {
    func testWriteReadRoundTrip() {
        let ring = AudioRingBuffer(capacity: 8)
        let input = Array(stride(from: Float(0), through: 5, by: 1))
        input.withUnsafeBufferPointer { XCTAssertEqual(ring.write($0), 6) }
        var output: [Float] = Array(repeating: 0, count: 8)
        let count = ring.read(into: &output, max: 8)
        XCTAssertEqual(count, 6)
        XCTAssertEqual(Array(output[0..<6]), input)
        XCTAssertEqual(ring.available, 0)
    }

    func testOverflowDropsOldestFreeSpace() {
        let ring = AudioRingBuffer(capacity: 4)
        let input = [Float](repeating: 1, count: 6)
        input.withUnsafeBufferPointer { XCTAssertEqual(ring.write($0), 4) }
        XCTAssertEqual(ring.available, 4)
    }

    func testEmptyRead() {
        let ring = AudioRingBuffer(capacity: 4)
        var output: [Float] = []
        XCTAssertEqual(ring.read(into: &output, max: 4), 0)
    }
}
