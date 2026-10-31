import XCTest
@testable import SuperflowHotkeyEngine

final class DictationConflictTests: XCTestCase {
    func testKnownCompetitorsMatchTheirNames() {
        XCTAssertEqual(DictationConflictPolicy.name(forBundleID: "com.seewillow.WillowMac"),
                       "Willow Voice")
        XCTAssertEqual(DictationConflictPolicy.name(forBundleID: "com.electron.wispr-flow"),
                       "Wispr Flow")
        XCTAssertEqual(DictationConflictPolicy.name(forBundleID: "com.superduper.superwhisper"),
                       "superwhisper")
    }

    /// The allowlist must stay narrow: a random app, the Finder, or Superflow
    /// itself can never be terminated by the conflict sweep.
    func testUnrelatedApplicationsAreNotCompetitors() {
        XCTAssertFalse(DictationConflictPolicy.isCompeting(bundleID: "com.apple.finder"))
        XCTAssertFalse(DictationConflictPolicy.isCompeting(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(DictationConflictPolicy.isCompeting(bundleID: "com.superflow.app"))
        XCTAssertNil(DictationConflictPolicy.name(forBundleID: "com.example.dictation"))
    }
}
