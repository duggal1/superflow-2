import Foundation
import SuperflowAppCore
import SuperflowFeatureHistory
import SuperflowKernel
import SuperflowStorageSQLite
import SuperflowTestKit
import XCTest

final class HistoryPersistenceObservationTests: XCTestCase {
    @MainActor
    func testSQLiteWriteAppearsInOpenHistoryWithinOneTenthSecond() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-history-observation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStoreFactory.open(url: directory.appendingPathComponent("history.sqlite"))
        let repository = PrivacyRepository(base: store)
        let model = HistoryViewModel(repository: repository, inserter: RecordingInserter())
        await model.load()
        let session = SessionRecord(id: SessionID("live"), kind: .dictation,
                                    status: .complete, modelProfile: "test")
        let started = ContinuousClock.now
        try await repository.createSession(session)
        while model.sessions.isEmpty && started.duration(to: .now) < .milliseconds(100) {
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(model.sessions.map(\.id), [session.id])
        XCTAssertLessThan(started.duration(to: .now), .milliseconds(100))
    }
}
