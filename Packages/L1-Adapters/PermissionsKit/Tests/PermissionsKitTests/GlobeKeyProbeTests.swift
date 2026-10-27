import Foundation
import SuperflowPorts
import XCTest
@testable import SuperflowPermissionsKit

final class GlobeKeyProbeTests: XCTestCase {
    private var suiteName: String!

    override func setUp() {
        suiteName = "com.superflow.tests.globe.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// A suite's search list also includes the global domain, so a key that is absent from the
    /// suite resolves to whatever this machine's global value is. Tests assert against that value
    /// rather than assuming the global preference was never written.
    private var globalRawValue: Int? {
        UserDefaults.standard.object(forKey: GlobeKeyOwnership.preferenceKey) as? Int
    }

    private func mapped(_ raw: Int?) -> GlobeKeyAction {
        switch raw {
        case nil: .notConfigured
        case 0: .doNothing
        case 1: .changeInputSource
        case 2: .emojiAndSymbols
        case 3: .dictation
        default: .unknown
        }
    }

    func testProbeReadsInjectedSuiteAndMapsEveryValue() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let probe = UserDefaultsGlobeKeyProbe(suiteName: suiteName)

        let absent = await probe.currentAction()
        XCTAssertEqual(absent, mapped(globalRawValue))

        defaults.set(0, forKey: GlobeKeyOwnership.preferenceKey)
        defaults.synchronize()
        let doNothing = await probe.currentAction()
        XCTAssertEqual(doNothing, .doNothing)

        defaults.set(1, forKey: GlobeKeyOwnership.preferenceKey)
        defaults.synchronize()
        let inputSource = await probe.currentAction()
        XCTAssertEqual(inputSource, .changeInputSource)

        defaults.set(2, forKey: GlobeKeyOwnership.preferenceKey)
        defaults.synchronize()
        let emoji = await probe.currentAction()
        XCTAssertEqual(emoji, .emojiAndSymbols)

        defaults.set(3, forKey: GlobeKeyOwnership.preferenceKey)
        defaults.synchronize()
        let dictation = await probe.currentAction()
        XCTAssertEqual(dictation, .dictation)

        defaults.set(99, forKey: GlobeKeyOwnership.preferenceKey)
        defaults.synchronize()
        let unknown = await probe.currentAction()
        XCTAssertEqual(unknown, .unknown)
    }

    func testProbeWithMissingSuiteFallsBackToStandardDefaults() async {
        let probe = UserDefaultsGlobeKeyProbe(suiteName: "com.superflow.tests.missing.\(UUID().uuidString)")
        let action = await probe.currentAction()
        XCTAssertEqual(action, mapped(globalRawValue))
    }

    /// macOS shows Emoji & Symbols for the Globe key when `AppleFnUsageType` was never written.
    /// That is the state of every first-run Mac, so it must read as a conflict Superflow can fix.
    func testUnsetPreferenceIsAConflictNotAnUnknown() {
        XCTAssertEqual(mapped(nil), .notConfigured)
        XCTAssertTrue(GlobeKeyAction.notConfigured.isConflict)
        XCTAssertFalse(GlobeKeyAction.unknown.isConflict)
        XCTAssertEqual(GlobeKeyAction.notConfigured.label, "Not set (shows Emoji & Symbols)")
    }

    /// Read-only check that the ownership helper reads the same global value the probe does. The
    /// write path is deliberately not exercised here: it would change the developer's own Globe
    /// binding. `AppCoordinator` calls it at launch.
    func testOwnershipReadsTheSameGlobalValueAsTheProbe() {
        XCTAssertEqual(GlobeKeyOwnership.rawValue(), globalRawValue)
    }
}
