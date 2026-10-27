import Foundation
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowStorageSQLite

final class SQLiteContractTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-contract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSQLiteSatisfiesTranscriptRepositoryContract() async throws {
        let store = try SQLiteStore(path: directory.appendingPathComponent("transcripts.sqlite").path)
        try await TranscriptRepositoryContract().verify(store)
    }

    func testSQLiteSatisfiesSettingsStoreContract() async throws {
        let store = try SQLiteStore(path: directory.appendingPathComponent("settings.sqlite").path)
        try await SettingsStoreContract().verify(store)
    }
}
