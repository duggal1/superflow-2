import XCTest
@testable import SuperflowUIComponents

final class InlineAudioTests: XCTestCase {
    func testClockFloorsTenthsWithoutOverflowingSeconds() {
        XCTAssertEqual(ClipClock.format(59.96), "0:59.9")
        XCTAssertEqual(ClipClock.format(60), "1:00.0")
        XCTAssertEqual(ClipClock.format(-1), "0:00.0")
        XCTAssertEqual(ClipClock.format(.infinity), "0:00.0")
    }

    func testWaveformSupportsMoreColumnsThanSamples() {
        let heights = TapePeaks.heights([0.5, -0.5], columns: 100)
        XCTAssertEqual(heights.count, 100)
        XCTAssertTrue(heights.allSatisfy { $0 <= 3 })
    }

    func testSilentClipHasNoTallCellsAndLoudClipHasPeaks() {
        XCTAssertEqual(TapePeaks.heights([Float](repeating: 0, count: 256), columns: 8), [UInt8](repeating: 0, count: 8))
        XCTAssertTrue(TapePeaks.heights([Float](repeating: 1, count: 256), columns: 8).allSatisfy { $0 == 3 })
        XCTAssertTrue(TapePeaks.heights([], columns: 8).isEmpty)
        XCTAssertTrue(TapePeaks.heights([1], columns: 0).isEmpty)
    }
}
