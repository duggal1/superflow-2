import Foundation
import XCTest
@testable import SuperflowAppCore

final class ApplicationInstanceLockTests: XCTestCase {
    @MainActor
    func testStartupCanRecoverAfterDirectoryFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocked directory".utf8).write(to: directory)
        let owner = AppCoordinatorOwner(supportDirectory: directory)
        XCTAssertNil(owner.coordinator.environment)
        XCTAssertNotNil(owner.coordinator.startupError)
        try FileManager.default.removeItem(at: directory)
        owner.retryStartup()
        XCTAssertNotNil(owner.coordinator.environment)
        XCTAssertNil(owner.coordinator.startupError)
    }

    func testSecondInstanceIsRejectedAndLockReleasesOnClose() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: ApplicationInstanceLock? = try ApplicationInstanceLock(directory: directory)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try ApplicationInstanceLock(directory: directory)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .EWOULDBLOCK)
        }
        first = nil
        let next = try ApplicationInstanceLock(directory: directory)
        withExtendedLifetime(next) {}
    }
}
