import Foundation
import XCTest
@testable import SuperflowKernel

final class CleanupPreferencesTests: XCTestCase {
    func testAutomaticListsDefaultToProseAndRoundTripWhenExplicitlyEnabled() throws {
        var settings = AppSettings()
        XCTAssertFalse(settings.implicitLists)
        settings.implicitLists = true
        XCTAssertEqual(settings.cleanupStructure, "lists")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.implicitLists)
        settings.implicitLists = false
        XCTAssertEqual(settings.cleanupStructure, "prose")
    }

    func testMigrationRestoresAutomaticListsWhileRespectingVersionFourOverrides() throws {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(AppSettings.self,
            from: Data(#"{"settingsVersion":2,"cleanupStructure":"prose","cleanupCompute":"cpu"}"#.utf8))
        XCTAssertEqual(legacy.cleanupStructure, "prose")
        XCTAssertEqual(legacy.cleanupCompute, .cpu)
        let oldListDefault = try decoder.decode(AppSettings.self,
            from: Data(#"{"settingsVersion":3,"cleanupStructure":"lists"}"#.utf8))
        XCTAssertEqual(oldListDefault.cleanupStructure, "prose")
        let explicit = try decoder.decode(AppSettings.self,
            from: Data(#"{"settingsVersion":4,"cleanupStructure":"lists"}"#.utf8))
        XCTAssertEqual(explicit.cleanupStructure, "lists")
    }
}
