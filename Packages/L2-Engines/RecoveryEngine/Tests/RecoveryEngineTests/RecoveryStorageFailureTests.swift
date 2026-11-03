import XCTest
import SuperflowKernel
import SuperflowTestKit
@testable import SuperflowRecoveryEngine

final class RecoveryStorageFailureTests: XCTestCase {
    func testReadFailureKeepsMeetingJournalForRetry() async throws {
        let repository = InMemoryRepository()
        let journal = FakeJournalStore()
        let session = SessionRecord(kind: .meeting, status: .recording, modelProfile: ModelProfile.default.id)
        try await repository.createSession(session)
        await journal.record(AudioChunk(samples: Array(repeating: 0.1, count: 1600), startSample: 0, source: .mic))
        await repository.setFailure(.read)
        let engine = RecoveryEngine(repository: repository, journals: journal, recognizer: FakeSpeechRecognizer())
        let report = await engine.recover()
        let remaining = await journal.sampleCount(session: session.id, source: .mic)
        let record = try await repository.session(session.id)
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.recovered, 0)
        XCTAssertEqual(remaining, 1600)
        XCTAssertEqual(record?.status, .recording)
        await repository.setFailure(nil)
        let retry = await engine.recover()
        XCTAssertEqual(retry.recovered, 1)
        let second = await engine.recover()
        XCTAssertEqual(second.scanned, 0)
    }

    func testCleanupWriteFailureKeepsJournalForRetry() async throws {
        let repository = InMemoryRepository()
        let journal = FakeJournalStore()
        let session = SessionRecord(kind: .meeting, status: .recording, modelProfile: ModelProfile.default.id)
        try await repository.createSession(session)
        try await repository.appendSegment(Segment(sessionID: session.id, index: 0, startMs: 0, endMs: 100, source: .mic, rawText: "hello"))
        await journal.record(AudioChunk(samples: Array(repeating: 0.1, count: 1600), startSample: 0, source: .mic))
        await repository.setFailure(.update)
        let engine = RecoveryEngine(repository: repository, journals: journal, recognizer: FakeSpeechRecognizer(), cleaner: { _ in RecoveryCleaned(text: "Hello.", state: .cleaned) })
        let report = await engine.recover()
        let remaining = await journal.sampleCount(session: session.id, source: .mic)
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.recovered, 0)
        XCTAssertEqual(remaining, 1600)
    }
}
