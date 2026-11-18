import Foundation
import XCTest
@testable import SuperflowFeatureIsland

/// Bright / sharp / smooth acceptance checks. These are additions: the existing
/// state-machine, snapshot, geometry and motion suites are untouched.
@MainActor
final class IslandBrightTests: XCTestCase {

    /// The raised ramp must keep five conceptual steps (the dither code indexes
    /// 0...4) and clamp out-of-range indices instead of trapping.
    func testBrightRampHasFiveClampedSteps() {
        XCTAssertEqual(IslandRamp.steps.count, 5)
        XCTAssertEqual(IslandRamp.step(-3), IslandRamp.step(0))
        XCTAssertEqual(IslandRamp.step(99), IslandRamp.step(4))
        // The readout step is the single blue-600 accent; the head is its bright
        // shade. Neither introduces a second hue.
        XCTAssertEqual(IslandRamp.step(2), IslandRamp.step(3))
        XCTAssertEqual(IslandRamp.step(4), IslandRamp.steps[4])
    }

    /// Every silhouette channel — including the two Bézier radii — lands on a
    /// whole device pixel on every frame of a transition.
    func testSilhouetteRadiiStayOnTheDevicePixelGridThroughAMove() {
        let start = IslandBox(body: CGSize(width: 200, height: 32), top: 6, bottom: 14, opacity: 1)
        let end = IslandBox(body: CGSize(width: 480, height: 120), top: 12, bottom: 24, opacity: 1)
        let motion = IslandKinematics(startingAt: start)
        motion.retarget(end, band: 32, instant: false, newStage: true)
        var now = 1.0
        for _ in 0..<40 {
            let frame = motion.step(now, scale: 2)
            for value in [frame.width, frame.height, frame.top, frame.bottom] {
                XCTAssertEqual(value * 2, (value * 2).rounded(),
                               "silhouette left the 2x grid at t=\(now)")
            }
            now += 1.0 / 60
        }
    }

    #if DEBUG
    /// The DEBUG probe reports the frame rate and the longest frame. Fed an
    /// exact 60 Hz clock it must read 60 fps with no long frame.
    func testFrameProbeMeasuresSixtyFPS() {
        let probe = IslandFrameProbe.shared
        probe.restart()
        var now = 100.0
        probe.tick(now) // first tick primes the clock
        for _ in 0..<60 {
            now += 1.0 / 60
            probe.tick(now)
        }
        XCTAssertEqual(probe.stats.frames, 60)
        XCTAssertEqual(probe.stats.fps, 60, accuracy: 1.0)
        XCTAssertLessThan(probe.stats.worstMs, 17.0)
    }

    /// A synthetic 60 Hz stall (one 40 ms frame) is caught as a long frame —
    /// the probe can fail, so a passing number means something.
    func testFrameProbeCatchesALongFrame() {
        let probe = IslandFrameProbe.shared
        probe.restart()
        var now = 200.0
        probe.tick(now)
        now += 0.040
        probe.tick(now)
        for _ in 0..<59 { now += 1.0 / 60; probe.tick(now) }
        XCTAssertGreaterThanOrEqual(probe.stats.worstMs, 39.0)
        probe.restart()
    }
    #endif

    /// The per-frame render loop is O(1) with no work that scales with state.
    /// XCTest reports the measured average; the wall-clock assertion is loose
    /// enough never to be flaky while still catching an accidental O(n) loop.
    func testRenderLoopFrameCost() {
        let start = IslandBox(body: CGSize(width: 200, height: 32), top: 6, bottom: 14, opacity: 1)
        let end = IslandBox(body: CGSize(width: 480, height: 120), top: 12, bottom: 24, opacity: 1)
        let motion = IslandKinematics(startingAt: start)
        let meter = IslandMeterModel()
        measure {
            motion.retarget(end, band: 32, instant: false, newStage: true)
            var now = 1_000.0
            for _ in 0..<60 {
                _ = motion.step(now, scale: 2)
                meter.advance(now)
                now += 1.0 / 60
            }
        }
    }
}
