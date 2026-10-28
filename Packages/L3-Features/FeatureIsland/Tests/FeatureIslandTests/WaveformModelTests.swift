import XCTest
@testable import SuperflowFeatureIsland

@MainActor
final class WaveformModelTests: XCTestCase {
    func testSilenceIsAFlatLine() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<20 { model.tick(level: 0) }
        XCTAssertEqual(model.history, [Int](repeating: 0, count: WaveformModel.historyCount))
    }

    func testStepInputRisesWithinThreeTicks() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<3 { model.tick(level: 1) }
        XCTAssertEqual(model.history[0], WaveformModel.halfMax)
    }

    func testReleaseDecaysToZeroWithinTwelveTicks() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<6 { model.tick(level: 1) }
        model.setLive(false)
        for _ in 0..<12 { model.tick(level: 1) }
        XCTAssertEqual(model.history, [Int](repeating: 0, count: WaveformModel.historyCount))
    }

    func testStoppedLiveAlwaysDecays() {
        let model = WaveformModel()
        model.tick(level: 1)
        model.tick(level: 1)
        model.tick(level: 1)
        XCTAssertEqual(model.history[0], 0)
    }

    func testValuesNeverLeaveTheRange() {
        let model = WaveformModel()
        model.setLive(true)
        for level in stride(from: Float(0), through: 4, by: 0.05) {
            model.tick(level: level)
            XCTAssertTrue((0...WaveformModel.halfMax).contains(model.history[0]))
        }
    }

    func testNoiseGateHoldsBelowFivePercent() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<30 { model.tick(level: 0.049) }
        XCTAssertEqual(model.history[0], 0)
    }

    func testHistoryKeepsOnlySixEntriesNewestFirst() {
        let model = WaveformModel()
        model.setLive(true)
        for _ in 0..<4 { model.tick(level: 1) }
        XCTAssertEqual(model.history.count, WaveformModel.historyCount)
        XCTAssertEqual(model.history[0], WaveformModel.halfMax)
        XCTAssertEqual(model.history[1], WaveformModel.halfMax)
    }
}
