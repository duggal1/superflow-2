import XCTest
import SuperflowKernel

/// The trigger-key picker is removed and its stored value is deleted on launch.
/// Uses an isolated UserDefaults suite so the real app defaults are untouched.
final class ClearlyInputMigrationTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "ClearlyInputMigrationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return .standard
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testLegacyTriggerPreference_isCleared() {
        let defaults = isolatedDefaults()
        defaults.set(IntelligenceTriggerKey.leftControl.rawValue,
                     forKey: IntelligenceTriggerMigration.legacyDefaultsKey)
        XCTAssertNotNil(defaults.object(forKey: IntelligenceTriggerMigration.legacyDefaultsKey))

        IntelligenceTriggerMigration.clear(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: IntelligenceTriggerMigration.legacyDefaultsKey))
    }

    func testClear_isIdempotent() {
        let defaults = isolatedDefaults()
        IntelligenceTriggerMigration.clear(defaults: defaults)
        IntelligenceTriggerMigration.clear(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: IntelligenceTriggerMigration.legacyDefaultsKey))
    }

    func testClear_leavesUnrelatedSettingsAlone() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "intelligence.screenAware")
        defaults.set(0, forKey: IntelligenceTriggerMigration.legacyDefaultsKey)
        IntelligenceTriggerMigration.clear(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: "intelligence.screenAware"))
    }

    func testLegacyKeyName_isTheDocumentedOne() {
        XCTAssertEqual(IntelligenceTriggerMigration.legacyDefaultsKey, "intelligence.trigger")
    }
}
