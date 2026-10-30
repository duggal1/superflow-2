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

    func testDelayedFrameCatchesUpToElapsedTime() {
        let start = IslandBox(body: CGSize(width: 200, height: 32), top: 6, bottom: 14, opacity: 1)
        let end = IslandBox(body: CGSize(width: 312, height: 32), top: 6, bottom: 14, opacity: 1)
        let motion = IslandKinematics(startingAt: start)
        motion.retarget(end, band: 32, instant: false)
        _ = motion.step(1, scale: 2)
        let frame = motion.step(1.5, scale: 2)
        XCTAssertGreaterThan(frame.width, 310)
    }

    /// The opening preset is deliberately underdamped, like iOS: a barely
    /// visible overshoot, then an exact landing. Closing stays at z = 1.
    func testOpeningPresetOvershootsSlightlyAndStillSettles() {
        var spring = Spring1(0)
        spring.target = 480
        var peak = 0.0
        for _ in 0..<360 {
            spring.step(1.0 / 120, omega: IslandMotion.open.width.w, zeta: IslandMotion.open.width.z)
            peak = max(peak, spring.x)
        }
        XCTAssertGreaterThan(peak, 480)
        XCTAssertLessThan(peak, 480 * 1.03)
        XCTAssertEqual(spring.x, 480, accuracy: 0.01)
    }

    /// The fade belongs to the scene, not the silhouette: a stage change resets
    /// it, a same-stage retarget leaves it at one.
    func testOnlyANewStageRestartsTheContentFade() {
        let start = IslandBox(body: CGSize(width: 200, height: 32), top: 6, bottom: 14, opacity: 1)
        let sameStage = IslandBox(body: CGSize(width: 240, height: 32), top: 6, bottom: 14, opacity: 1)
        let newStage = IslandBox(body: CGSize(width: 480, height: 120), top: 12, bottom: 24, opacity: 1)

        let continuing = IslandKinematics(startingAt: start)
        continuing.retarget(sameStage, band: 32, instant: false, newStage: false)
        XCTAssertEqual(continuing.step(1, scale: 2).fade, 1, accuracy: 0.0001)

        let changing = IslandKinematics(startingAt: start)
        changing.retarget(newStage, band: 32, instant: false, newStage: true)
        XCTAssertLessThan(changing.step(1, scale: 2).fade, 0.01)
    }

    /// A success kick adds velocity to both silhouette channels without moving
    /// them on the spot; the next frame carries the impulse.
    func testSuccessBumpAddsAnImpulseWithoutJumpingTheShape() {
        let box = IslandBox(body: CGSize(width: 200, height: 32), top: 6, bottom: 14, opacity: 1)
        let motion = IslandKinematics(startingAt: box)
        motion.bump(width: 3, height: 1.5)
        let first = motion.step(1, scale: 2)
        let second = motion.step(1.05, scale: 2)
        XCTAssertEqual(first.width, 200)
        XCTAssertGreaterThan(second.width, 200)
        XCTAssertGreaterThan(second.height, 32)
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
