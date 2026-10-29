import Foundation
import XCTest
@testable import SuperflowKernel

final class CleanupPreferencesTests: XCTestCase {
    func testImplicitListsDefaultOffAndRoundTripThroughExistingSetting() throws {
        var settings = AppSettings()
        XCTAssertFalse(settings.implicitLists)
        settings.implicitLists = true
        XCTAssertEqual(settings.cleanupStructure, "lists")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.implicitLists)
        settings.implicitLists = false
        XCTAssertEqual(settings.cleanupStructure, "prose")
    }
}
