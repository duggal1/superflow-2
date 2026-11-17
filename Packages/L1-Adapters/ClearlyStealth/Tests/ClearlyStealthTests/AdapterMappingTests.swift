import XCTest
import AppKit
@testable import ClearlyStealth
@testable import ClearlyStealthCore

/// Compile-and-mapping checks only. No window is created, no GUI is opened,
/// no capture is performed — safe for headless runners.
final class AdapterMappingTests: XCTestCase {
    func testSharingModeMapsToPublicAppKitFlag() {
        XCTAssertEqual(StealthSharingMode.none.nsSharingType, .none)
        XCTAssertEqual(StealthSharingMode.readOnly.nsSharingType, .readOnly)
        XCTAssertEqual(StealthSharingMode.readWrite.nsSharingType, .readWrite)
    }

    func testOSBuildIsNonEmpty() {
        XCTAssertFalse(StealthSystem.currentOSBuild().isEmpty)
    }
}
