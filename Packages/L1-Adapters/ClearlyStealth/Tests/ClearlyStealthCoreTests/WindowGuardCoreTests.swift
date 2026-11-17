import XCTest
@testable import ClearlyStealthCore

@MainActor
private final class FakeWindow: WindowSharingControllable {
    var sharingMode: StealthSharingMode
    init(_ mode: StealthSharingMode) { sharingMode = mode }
}

@MainActor
final class WindowGuardCoreTests: XCTestCase {
    func testEnforceForcesEveryWindowToNoneOnEveryEvent() {
        for event in [StealthWindowEvent.windowUpdated, .screenParametersChanged,
                      .spaceChanged, .wake, .islandShown, nil] {
            let windows: [FakeWindow] = [.init(.readOnly), .init(.readWrite), .init(.none)]
            let guard_ = WindowGuardCore(windowProvider: { windows })
            let corrected = guard_.enforce(on: event)
            XCTAssertEqual(corrected, 2)
            XCTAssertTrue(windows.allSatisfy { $0.sharingMode == .none })
        }
    }

    func testEnforceIsIdempotent() {
        let windows: [FakeWindow] = [.init(.readOnly), .init(.readWrite)]
        let guard_ = WindowGuardCore(windowProvider: { windows })
        XCTAssertEqual(guard_.enforce(), 2)
        XCTAssertEqual(guard_.enforce(), 0)
        XCTAssertTrue(windows.allSatisfy { $0.sharingMode == .none })
    }

    func testIslandShowReappliesAfterANewCapturableWindowAppears() {
        var windows: [FakeWindow] = [.init(.none)]
        let guard_ = WindowGuardCore(windowProvider: { windows })
        XCTAssertEqual(guard_.enforce(on: .islandShown), 0)
        windows.append(FakeWindow(.readOnly))  // e.g. a SwiftUI popover appeared
        XCTAssertEqual(guard_.enforce(on: .islandShown), 1)
        XCTAssertTrue(windows.allSatisfy { $0.sharingMode == .none })
    }

    func testInvariantAssertionIsInvokedWithTheWindowSet() {
        let windows: [FakeWindow] = [.init(.none), .init(.readOnly)]
        var asserted: [[StealthSharingMode]] = []
        let guard_ = WindowGuardCore(windowProvider: { windows }, invariantAssertion: { observed in
            asserted.append(observed.map(\.sharingMode))
        })
        guard_.enforce(on: .windowUpdated)
        XCTAssertEqual(asserted.count, 1)
        XCTAssertEqual(asserted.first, [.none, .none])
    }

    func testEmptyWindowSetIsHarmless() {
        let guard_ = WindowGuardCore(windowProvider: { [] })
        XCTAssertEqual(guard_.enforce(on: .wake), 0)
    }
}
