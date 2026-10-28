import Foundation
import XCTest
@testable import SuperflowAppCore

/// The gate reads `AppSettings.onboardingComplete`. This proves the launch-time
/// fallback: a database that lost the flag (or never had it) cannot send an owner
/// who already finished setup back through onboarding.
final class OnboardingCheckpointTests: XCTestCase {
    private var suiteName = ""

    private func makeDefaults() -> UserDefaults {
        suiteName = "OnboardingCheckpointTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { [suiteName] in
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testCheckpointStartsIncompleteAndStaysCompleteOnceMarked() {
        let defaults = makeDefaults()
        XCTAssertFalse(OnboardingCheckpoint.isComplete(in: defaults))
        OnboardingCheckpoint.markComplete(in: defaults)
        XCTAssertTrue(OnboardingCheckpoint.isComplete(in: defaults))
    }

    func testCheckpointIsScopedToItsOwnStore() {
        let defaults = makeDefaults()
        OnboardingCheckpoint.markComplete(in: defaults)
        XCTAssertTrue(OnboardingCheckpoint.isComplete(in: defaults))
        XCTAssertFalse(OnboardingCheckpoint.isComplete(in: makeDefaults()))
    }
}
