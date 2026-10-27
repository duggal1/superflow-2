import XCTest
import SuperflowKernel
@testable import SuperflowTestKit

final class RepositoryTests: XCTestCase {
    func testPurgeKeepsActiveSessionsAndRemovesExpiredCompletedSessions() async throws {
        let repository = InMemoryRepository()
        let cutoff = Date(timeIntervalSince1970: 2_000)
        let old = SessionRecord(id: SessionID("old"), kind: .dictation,
                                startedAt: Date(timeIntervalSince1970: 1_000),
                                status: .complete, modelProfile: ModelProfile.parakeetEOU120M.id)
        let active = SessionRecord(id: SessionID("active"), kind: .meeting,
                                   startedAt: Date(timeIntervalSince1970: 1_000),
                                   status: .recording, modelProfile: ModelProfile.parakeetEOU120M.id)
        try await repository.createSession(old)
        try await repository.createSession(active)

        let removed = try await repository.purge(olderThan: cutoff)
        let oldAfterPurge = try await repository.session(old.id)
        let activeAfterPurge = try await repository.session(active.id)

        XCTAssertEqual(removed, 1)
        XCTAssertNil(oldAfterPurge)
        XCTAssertEqual(activeAfterPurge?.status, .recording)
    }
}
