import Foundation
import XCTest
@testable import SuperflowKernel

final class CleanupPreferencesTests: XCTestCase {
    func testImplicitListsDefaultOnAndRoundTripThroughExistingSetting() throws {
        var settings = AppSettings()
        XCTAssertTrue(settings.implicitLists)
        settings.implicitLists = true
        XCTAssertEqual(settings.cleanupStructure, "lists")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.implicitLists)
        settings.implicitLists = false
        XCTAssertEqual(settings.cleanupStructure, "prose")
    }

    func testListDefaultMigrationPreservesNewerChoicesAndCPU() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(AppSettings.self, from: Data(#"{"settingsVersion":2,"cleanupStructure":"prose","cleanupCompute":"cpu"}"#.utf8))
        XCTAssertEqual(old.cleanupStructure, "lists")
        XCTAssertEqual(old.cleanupCompute, .cpu)
        let explicit = try decoder.decode(AppSettings.self, from: Data(#"{"settingsVersion":3,"cleanupStructure":"prose","cleanupCompute":"cpu"}"#.utf8))
        XCTAssertEqual(explicit.cleanupStructure, "prose")
        XCTAssertEqual(explicit.cleanupCompute, .cpu)
    }
}
