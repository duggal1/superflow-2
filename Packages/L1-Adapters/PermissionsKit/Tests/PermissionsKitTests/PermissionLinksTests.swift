import SuperflowPorts
import XCTest
@testable import SuperflowPermissionsKit

final class PermissionLinksTests: XCTestCase {
    func testEveryPermissionHasADeepLink() {
        for permission in Permission.allCases {
            let url = PermissionLinks.url(for: permission)
            XCTAssertNotNil(url, "missing link for \(permission)")
            XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
        }
    }

    func testAnchorsMatchSystemSettingsPanes() {
        XCTAssertEqual(PermissionLinks.url(for: .microphone)?.absoluteString,
                       "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")
        XCTAssertEqual(PermissionLinks.url(for: .accessibility)?.absoluteString,
                       "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
        XCTAssertEqual(PermissionLinks.url(for: .inputMonitoring)?.absoluteString,
                       "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")
        XCTAssertEqual(PermissionLinks.url(for: .systemAudio)?.absoluteString,
                       "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")
    }

    func testEachPermissionHasALegacyFallback() {
        for permission in Permission.allCases {
            let fallback = PermissionLinks.fallbackURL(for: permission)
            XCTAssertEqual(fallback?.scheme, "x-apple.systempreferences")
            XCTAssertTrue(fallback?.absoluteString.contains("com.apple.preference.security") == true)
        }
    }

    func testSummarySeparatesGrantedAndMissing() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .accessibility: .denied,
            .inputMonitoring: .notDetermined,
        ]
        XCTAssertEqual(PermissionSummary.granted(statuses), [.microphone])
        XCTAssertEqual(PermissionSummary.missing(statuses),
                       [.accessibility, .inputMonitoring, .systemAudio])
    }

    func testStatusIsGrantedOnlyWhenGranted() {
        XCTAssertTrue(PermissionStatus.granted.isGranted)
        XCTAssertFalse(PermissionStatus.denied.isGranted)
        XCTAssertFalse(PermissionStatus.notDetermined.isGranted)
    }

    func testEveryPermissionExplainsItself() {
        for permission in Permission.allCases {
            XCTAssertFalse(permission.label.isEmpty)
            XCTAssertFalse(permission.rationale.isEmpty)
            XCTAssertTrue(permission.rationale.contains("Superflow") || permission.rationale.contains("Audio"))
        }
    }
}
