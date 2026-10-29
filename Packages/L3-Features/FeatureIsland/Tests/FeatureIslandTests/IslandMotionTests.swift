import AppKit
import SwiftUI
import XCTest
@testable import SuperflowFeatureIsland

@MainActor
final class IslandMotionTests: XCTestCase {
    func testEnlargedArtworkStaysOnPhysicalPixels() {
        for scale: CGFloat in [1, 2] {
            let grid = IslandPixelGrid(scale: scale)
            let width = grid.length(32)
            XCTAssertGreaterThanOrEqual(width / 32, 1.05)
            XCTAssertLessThanOrEqual(width / 32, 1.10)
            for column in 0..<24 {
                let rect = grid.rect(CGRect(x: CGFloat(column) * 3, y: 3, width: 2, height: 2))
                for value in [rect.minX, rect.minY, rect.maxX, rect.maxY] {
                    XCTAssertEqual(value * scale, (value * scale).rounded())
                }
            }
        }
    }

    func testSpringIsIndependentOfFrameRateAndLandsExactly() {
        var sixty = Spring1(0)
        var oneTwenty = Spring1(0)
        sixty.target = 480
        oneTwenty.target = 480
        for _ in 0..<60 { sixty.step(1.0 / 60, omega: 15) }
        for _ in 0..<120 { oneTwenty.step(1.0 / 120, omega: 15) }
        XCTAssertEqual(sixty.x, oneTwenty.x, accuracy: 0.000001)
        XCTAssertLessThan(sixty.x, 480)
        sixty.land()
        XCTAssertEqual(sixty.x, 480)
        XCTAssertEqual(sixty.v, 0)
    }

    func testRetargetKeepsCurrentPositionAndVelocity() {
        var spring = Spring1(0)
        spring.target = 480
        spring.step(0.1, omega: 15)
        let position = spring.x
        let velocity = spring.v
        spring.target = 280
        XCTAssertEqual(spring.x, position)
        XCTAssertEqual(spring.v, velocity)
        spring.step(1.0 / 120, omega: 15)
        XCTAssertGreaterThan(spring.x, position)
    }

    func testNoSignalShelfReservesSpaceAndHistoryFitsItsRows() {
        let geometry = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     safeTop: 32, leftWidth: 620, rightWidth: 620, scale: 2)
        XCTAssertEqual(IslandLayout.box(.listening, geometry, noSignal: true).body.height, 64)
        XCTAssertEqual(IslandLayout.box(.history, geometry, historyRows: 0).body.height, 160)
        XCTAssertEqual(IslandLayout.box(.history, geometry, historyRows: 5).body.height, 280)
        XCTAssertEqual(IslandLayout.box(.meetingPanel, geometry, live: true).body.height, 240)
    }

    func testMeterRetainsPeakAndIgnoresRepeatedFrame() {
        let meter = IslandMeterModel()
        meter.ingest(0.9)
        meter.advance(1)
        let shown = meter.shown
        meter.advance(1)
        XCTAssertEqual(meter.shown, shown)
        meter.advance(1.04)
        XCTAssertGreaterThan(meter.trail[0], 0.8)
        XCTAssertTrue(meter.heard)
        meter.reset()
        XCTAssertFalse(meter.heard)
        XCTAssertEqual(meter.shown, 0)
    }
}
