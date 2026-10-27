import XCTest
@testable import SuperflowHotkeyEngine

final class HotkeyLifecycleTests: XCTestCase {
    func testStartIsIdempotentWhileRunning() {
        var lifecycle = HotkeyLifecycle()
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertTrue(lifecycle.isRunning)
        XCTAssertFalse(lifecycle.beginStart())
        XCTAssertTrue(lifecycle.isRunning)
    }

    func testStopIsIdempotentWhenStopped() {
        var lifecycle = HotkeyLifecycle()
        XCTAssertFalse(lifecycle.beginStop())
        XCTAssertFalse(lifecycle.isRunning)
    }

    func testFailedStartRollsBackSoNextStartRetries() {
        var lifecycle = HotkeyLifecycle()
        XCTAssertTrue(lifecycle.beginStart())
        lifecycle.startFailed()
        XCTAssertFalse(lifecycle.isRunning)
        XCTAssertTrue(lifecycle.beginStart())
    }

    func testStopThenStartAllowsReinstallAfterPermissionRegrant() {
        var lifecycle = HotkeyLifecycle()
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertTrue(lifecycle.beginStop())
        XCTAssertFalse(lifecycle.isRunning)
        XCTAssertTrue(lifecycle.beginStart())
        XCTAssertTrue(lifecycle.isRunning)
    }
}
