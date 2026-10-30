import Foundation
import SuperflowKernel
import SuperflowStorageSQLite
import XCTest
@testable import SuperflowAppCore

final class ApplicationInstanceLockTests: XCTestCase {
    func testDiskFullStartupMessageAsksForSpaceAndPromisesDataIsSafe() {
        let error = SQLiteError(code: 10, message: "disk I/O error",
                                sql: "PRAGMA journal_mode=WAL",
                                extendedCode: 4618, systemCode: 28)
        let message = AppCoordinator.startupMessage(for: error)
        XCTAssertTrue(message.contains("free disk space"))
        XCTAssertTrue(message.contains("Try again"))
        XCTAssertTrue(message.contains("untouched"))
    }

    func testOtherOpenFailuresKeepTheUnderlyingDetail() {
        let error = SQLiteError(code: 14, message: "unable to open database file")
        let message = AppCoordinator.startupMessage(for: error)
        XCTAssertTrue(message.contains("could not open its local database"))
        XCTAssertTrue(message.contains("unable to open database file"))
    }

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
