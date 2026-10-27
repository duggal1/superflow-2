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

    func testProbeReadsInjectedSuiteAndMapsEveryValue() async {
        let defaults = UserDefaults(suiteName: suiteName)!
        let probe = UserDefaultsGlobeKeyProbe(suiteName: suiteName)

        let absent = await probe.currentAction()
        XCTAssertEqual(absent, .unknown)

        defaults.set(0, forKey: "AppleFnUsageType")
        defaults.synchronize()
        let doNothing = await probe.currentAction()
        XCTAssertEqual(doNothing, .doNothing)

        defaults.set(1, forKey: "AppleFnUsageType")
        defaults.synchronize()
        let inputSource = await probe.currentAction()
        XCTAssertEqual(inputSource, .changeInputSource)

        defaults.set(2, forKey: "AppleFnUsageType")
        defaults.synchronize()
        let emoji = await probe.currentAction()
        XCTAssertEqual(emoji, .emojiAndSymbols)

        defaults.set(3, forKey: "AppleFnUsageType")
        defaults.synchronize()
        let dictation = await probe.currentAction()
        XCTAssertEqual(dictation, .dictation)

        defaults.set(99, forKey: "AppleFnUsageType")
        defaults.synchronize()
        let unknown = await probe.currentAction()
        XCTAssertEqual(unknown, .unknown)
    }

    func testProbeWithMissingSuiteFallsBackToStandardDefaults() async {
        let probe = UserDefaultsGlobeKeyProbe(suiteName: "com.superflow.tests.missing.\(UUID().uuidString)")
        let action = await probe.currentAction()
        XCTAssertEqual(action, .unknown)
    }
}
