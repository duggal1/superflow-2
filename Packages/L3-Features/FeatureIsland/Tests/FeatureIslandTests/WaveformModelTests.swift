import XCTest
@testable import SuperflowFeatureIsland

@MainActor
final class WaveformModelTests: XCTestCase {
    private let silence = [Float](repeating: 0, count: WaveformModel.depth)

    func testSilenceIsAFlatTrail() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<20 { model.tick(level: 0) }
        XCTAssertEqual(model.trail, silence)
    }

    func testStepInputLightsTheTopCellWithinThreeTicks() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<3 { model.tick(level: 1) }
        XCTAssertEqual(WaveformModel.cells(model.trail[0], max: WaveformModel.halfMax),
                       WaveformModel.halfMax)
    }

    func testReleaseDecaysToZero() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<6 { model.tick(level: 1) }
        model.setLive(false)
        for _ in 0..<60 { model.tick(level: 1) }
        XCTAssertEqual(model.trail, silence)
    }

    func testStoppedLiveAlwaysDecays() {
        let model = WaveformModel()
        model.tick(level: 1)
        model.tick(level: 1)
        model.tick(level: 1)
        XCTAssertEqual(model.trail, silence)
    }

    func testValuesNeverLeaveTheRange() {
        let model = WaveformModel()
        model.setLive(true)
        for level in stride(from: Float(0), through: 4, by: 0.05) {
            model.tick(level: level)
            XCTAssertTrue((0...1).contains(model.trail[0]))
            XCTAssertTrue((0...WaveformModel.halfMax)
                .contains(WaveformModel.cells(model.trail[0], max: WaveformModel.halfMax)))
        }
    }

    /// The old meter gated at five percent and drew silence in near-black, so a
    /// normal speaking voice near the gate looked like a dead meter. The gate is
    /// now four percent, and it must light a cell at the smallest real signal.
    func testGateHoldsBelowFourPercentAndLightsAtIt() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<30 { model.tick(level: 0.039) }
        XCTAssertEqual(model.trail[0], 0)
        XCTAssertEqual(WaveformModel.cells(0.039, max: WaveformModel.halfMax), 0)

        for _ in 0..<30 { model.tick(level: 0.04) }
        XCTAssertGreaterThan(WaveformModel.cells(model.trail[0], max: WaveformModel.halfMax), 0)
        XCTAssertEqual(WaveformModel.cells(0.04, max: WaveformModel.halfMax), 1)
    }

    func testTrailKeepsOneFramePerEntryNewestFirst() {
        let model = WaveformModel()
        model.setLive(true)
        model.tick(level: 1)
        let first = model.trail[0]
        XCTAssertEqual(model.trail.count, WaveformModel.depth)
        model.tick(level: 0.5)
        XCTAssertEqual(model.trail[1], first)
        XCTAssertLessThan(model.trail[0], first)
        XCTAssertEqual(model.trail[WaveformModel.depth - 1], 0)
    }

    func testResetClearsTheSession() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<5 { model.tick(level: 1) }
        model.reset()
        XCTAssertEqual(model.trail, silence)
        // And a reset leaves the model not-live: the next frame must not spring
        // back to the pre-reset level.
        model.tick(level: 1)
        XCTAssertEqual(model.trail, silence)
    }

    func testCellMapIsMonotonic() {
        var last = 0
        for step in stride(from: Float(0), through: 1, by: 0.02) {
            let cells = WaveformModel.cells(step, max: WaveformModel.halfMax)
            XCTAssertGreaterThanOrEqual(cells, last)
            last = cells
        }
        XCTAssertEqual(WaveformModel.cells(1, max: WaveformModel.halfMax), WaveformModel.halfMax)
    }
}
