import SuperflowPorts
import XCTest
@testable import SuperflowPermissionsKit

/// Pins the distinction that the Input Monitoring bug violated: a permission the app has never
/// asked for must report `.notDetermined` so the UI raises the system prompt, while one the user
/// has already answered must report `.denied` so the UI sends them to System Settings.
final class PermissionDecisionTests: XCTestCase {
    func testGrantedIsGrantedRegardlessOfAsked() {
        XCTAssertEqual(PermissionDecision.resolve(probe: .granted, asked: false), .granted)
        XCTAssertEqual(PermissionDecision.resolve(probe: .granted, asked: true), .granted)
    }

    func testNeverAskedIsNotDeterminedSoTheAppCanPrompt() {
        XCTAssertEqual(PermissionDecision.resolve(probe: .notGranted, asked: false), .notDetermined)
    }

    func testAnsweredButNotGrantedIsDenied() {
        XCTAssertEqual(PermissionDecision.resolve(probe: .notGranted, asked: true), .denied)
    }

    func testExplicitUndeterminedPassesThrough() {
        XCTAssertEqual(PermissionDecision.resolve(probe: .undetermined, asked: false), .notDetermined)
        XCTAssertEqual(PermissionDecision.resolve(probe: .undetermined, asked: true), .notDetermined)
    }

    func testMicrophoneAuthorizationMapsDirectly() {
        XCTAssertEqual(PermissionDecision.microphone(authorization: .granted), .granted)
        XCTAssertEqual(PermissionDecision.microphone(authorization: .denied), .denied)
        XCTAssertEqual(PermissionDecision.microphone(authorization: .undetermined), .notDetermined)
    }
}
