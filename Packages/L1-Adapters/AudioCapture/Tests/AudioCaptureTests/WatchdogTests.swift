import XCTest
@testable import SuperflowAudioCapture

final class WatchdogTests: XCTestCase {
    func testStalledAndAlwaysZeroAreIndependent() {
        var watchdog = CaptureWatchdog(now: 0, stalledAfter: 100, zeroAfter: 200)
        // Zeros keep arriving: the route is progressing but carries no signal.
        watchdog.observe(samples: [0, 0, 0], dropped: 0, now: 10)
        watchdog.check(now: 120)
        XCTAssertTrue(watchdog.health.stalled)
        XCTAssertFalse(watchdog.health.alwaysZero)

        watchdog.check(now: 210)
        XCTAssertTrue(watchdog.health.alwaysZero)
        XCTAssertFalse(watchdog.health.overflowed)
    }

    func testSignalClearsAlwaysZeroWithoutTouchingOverflow() {
        var watchdog = CaptureWatchdog(now: 0, stalledAfter: 100, zeroAfter: 50)
        watchdog.check(now: 60)
        XCTAssertTrue(watchdog.health.alwaysZero)
        XCTAssertFalse(watchdog.health.stalled)

        watchdog.observe(samples: [0.4], dropped: 2, now: 70)
        XCTAssertFalse(watchdog.health.alwaysZero)
        XCTAssertTrue(watchdog.health.overflowed)
        XCTAssertFalse(watchdog.health.stalled)
    }

    func testOverflowLatchesUntilReset() {
        var watchdog = CaptureWatchdog(now: 0)
        watchdog.observe(samples: [1], dropped: 5, now: 1)
        XCTAssertTrue(watchdog.health.overflowed)
        watchdog.observe(samples: [1], dropped: 0, now: 2)
        XCTAssertTrue(watchdog.health.overflowed)
        watchdog.reset(now: 3)
        XCTAssertFalse(watchdog.health.overflowed)
        XCTAssertFalse(watchdog.health.stalled)
        XCTAssertFalse(watchdog.health.alwaysZero)
    }

    func testRouteRebuildHasItsOwnTimeout() {
        var watchdog = CaptureWatchdog(now: 0, rebuildTimeout: 100)
        watchdog.beginRebuild(now: 10)
        XCTAssertTrue(watchdog.health.rebuildingRoute)
        XCTAssertFalse(watchdog.health.rebuildTimedOut)

        // The rebuild started at 10 and times out after 100 ns.
        watchdog.check(now: 109)
        XCTAssertFalse(watchdog.health.rebuildTimedOut)
        watchdog.check(now: 110)
        XCTAssertTrue(watchdog.health.rebuildTimedOut)
        XCTAssertTrue(watchdog.health.rebuildingRoute)

        watchdog.endRebuild(now: 2_000)
        XCTAssertFalse(watchdog.health.rebuildingRoute)
        XCTAssertFalse(watchdog.health.rebuildTimedOut)
        XCTAssertFalse(watchdog.health.stalled)
        XCTAssertFalse(watchdog.health.alwaysZero)
    }

    func testPrepareNeverOpensTheDeviceAndStartDoes() {
        var lifecycle = CaptureLifecycle()
        XCTAssertFalse(lifecycle.isPrepared)
        XCTAssertFalse(lifecycle.mayOpenDevice)

        lifecycle.prepare()
        XCTAssertTrue(lifecycle.isPrepared)
        XCTAssertFalse(lifecycle.mayOpenDevice, "launch preparation must leave the mic closed")

        lifecycle.start()
        XCTAssertTrue(lifecycle.mayOpenDevice, "first key-down may open the device")

        lifecycle.stop()
        XCTAssertFalse(lifecycle.mayOpenDevice)
        XCTAssertFalse(lifecycle.isPrepared)
    }
}
