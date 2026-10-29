import Foundation
import XCTest
@testable import SuperflowAudioCapture

final class MicrophoneTests: XCTestCase, @unchecked Sendable {
    func testLiveCaptureDeliversSignalAndRestarts() async throws {
        guard ProcessInfo.processInfo.environment["SUPERFLOW_TEST_MICROPHONE"] == "1" else {
            throw XCTSkip("Opt in to real microphone capture with SUPERFLOW_TEST_MICROPHONE=1")
        }
        let microphone = MicrophoneCapture()
        for _ in 0..<2 {
            let streams = try await microphone.start()
            let collector = Task { () -> (Int, Float, Bool) in
                var count = 0
                var peak: Float = 0
                var continuous = true
                for await chunk in streams.samples {
                    continuous = continuous && chunk.startSample == Int64(count)
                    count += chunk.samples.count
                    peak = max(peak, chunk.samples.map(abs).max() ?? 0)
                }
                return (count, peak, continuous)
            }
            try await Task.sleep(for: .seconds(2))
            await microphone.stop()
            let (count, peak, continuous) = await collector.value
            XCTAssertGreaterThan(count, 16_000)
            XCTAssertGreaterThan(peak, 0)
            XCTAssertTrue(continuous)
        }
    }

    func testInterleavedInputSelectsFirstChannel() {
        let ring = AudioRingBuffer(capacity: 4)
        let stereo: [Float] = [1, -1, 2, -2, 3, -3]
        stereo.withUnsafeBufferPointer { XCTAssertEqual(ring.write($0, stride: 2), 3) }
        var result = [Float](repeating: 0, count: 4)
        XCTAssertEqual(ring.read(into: &result, max: 4), 3)
        XCTAssertEqual(Array(result.prefix(3)), [1, 2, 3])
    }
}
