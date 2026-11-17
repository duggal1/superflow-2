import XCTest
@testable import ClearlyStealthCore

final class StealthStatusAndExclusionTests: XCTestCase {
    // MARK: - Screen reader self-exclusion (recognizer-independent)

    func testIslandIsExcludedByOwnProcess() {
        let island = WindowIdentity(pid: 42, bundleIdentifier: "com.superflow.app")
        let sameProcess = WindowIdentity(pid: 42, bundleIdentifier: nil)
        XCTAssertTrue(ScreenCaptureExclusion.shouldExclude(sameProcess, island: island))
    }

    func testOtherWindowOfSameProcessIsExcluded() {
        let island = WindowIdentity(pid: 42, bundleIdentifier: "com.superflow.app")
        let sibling = WindowIdentity(pid: 42, bundleIdentifier: "com.superflow.app")
        XCTAssertTrue(ScreenCaptureExclusion.shouldExclude(sibling, island: island))
    }

    func testUnrelatedWindowIsNotExcluded() {
        let island = WindowIdentity(pid: 42, bundleIdentifier: "com.superflow.app")
        let chrome = WindowIdentity(pid: 99, bundleIdentifier: "com.google.Chrome")
        XCTAssertFalse(ScreenCaptureExclusion.shouldExclude(chrome, island: island))
    }

    func testNilBundleOtherProcessIsNotExcluded() {
        let island = WindowIdentity(pid: 42, bundleIdentifier: "com.superflow.app")
        let other = WindowIdentity(pid: 43, bundleIdentifier: nil)
        XCTAssertFalse(ScreenCaptureExclusion.shouldExclude(other, island: island))
    }

    // MARK: - Honest status copy

    func testNoRecordIsUnverifiedWithBadge() {
        let presentation = StealthCopy.presentation(for: nil)
        XCTAssertEqual(presentation.title, "Hiding not verified")
        XCTAssertNotNil(presentation.badge)
        XCTAssertFalse(StealthCopyContainsForbiddenClaim(presentation))
    }

    func testVerifiedCopyIncludesBuildAndBoundsTheClaim() {
        let record = StealthStatusRecord(status: .verified, osBuild: "26B123",
                                         displayConfiguration: "x")
        let presentation = StealthCopy.presentation(for: record)
        XCTAssertTrue(presentation.title.contains("Hidden from screen capture on this Mac"))
        XCTAssertTrue(presentation.detail.contains("26B123"))
        XCTAssertTrue(presentation.detail.contains("share modes were not tested"))
        XCTAssertNil(presentation.badge)
        XCTAssertFalse(StealthCopyContainsForbiddenClaim(presentation))
    }

    func testFailedCopyWarnsLoudly() {
        let record = StealthStatusRecord(status: .failed, osBuild: "26B123",
                                         displayConfiguration: "x")
        let presentation = StealthCopy.presentation(for: record)
        XCTAssertTrue(presentation.title.contains("Visible to screen share"))
        XCTAssertTrue(presentation.detail.contains("Do not rely on hiding"))
        XCTAssertEqual(presentation.badge, "Visible in share")
        XCTAssertFalse(StealthCopyContainsForbiddenClaim(presentation))
    }

    func testNoCopyPromisesTotalInvisibility() {
        for status in [StealthStatus.verified, .failed, .unverified] {
            let record = StealthStatusRecord(status: status, osBuild: "26B123",
                                             displayConfiguration: "x")
            XCTAssertFalse(StealthCopyContainsForbiddenClaim(StealthCopy.presentation(for: record)))
        }
    }

    private func StealthCopyContainsForbiddenClaim(_ p: StealthPresentation) -> Bool {
        let text = (p.title + " " + p.detail + " " + (p.badge ?? "")).lowercased()
        return text.contains("undetectable") || text.contains("invisible to everything") ||
               text.contains("un detectable") || text.contains("guaranteed")
    }
}
