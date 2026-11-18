import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowRecoveryEngine

/// A store that claims samples exist but yields no replay data — the "audio file vanished" shape.
private actor MissingAudioJournal: JournalStore {
    private let real: FileBackedJournalStore
    init(_ real: FileBackedJournalStore) { self.real = real }
    func openWriter(session: SessionID, source: AudioSourceKind, startingSample: Int64) async throws -> any AudioJournalWriter {
        try await real.openWriter(session: session, source: source, startingSample: startingSample)
    }
    func replay(session: SessionID, source: AudioSourceKind, fromSample: Int64) async -> AsyncStream<AudioChunk> {
        AsyncStream { $0.finish() }
    }
    func sessionsWithJournals() async -> [SessionID] { await real.sessionsWithJournals() }
    func sampleCount(session: SessionID, source: AudioSourceKind) async -> Int64 {
        await real.sampleCount(session: session, source: source)
    }
    func delete(session: SessionID) async { await real.delete(session: session) }
    func freeBytes() async -> Int64 { Int64.max }
}

final class RecoveryEdgeCaseTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws { root = RecoveryTestSupport.tempRoot("edge") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func fixture(status: SessionStatus = .recording, withJournal: Bool = true) async throws
        -> (repo: InMemoryRepository, journal: FileBackedJournalStore, session: SessionRecord) {
        let repo = InMemoryRepository()
        let journal = FileBackedJournalStore(root: root.appendingPathComponent("Journals", isDirectory: true))
        let session = SessionRecord(kind: .dictation, status: status, modelProfile: ModelProfile.default.id)
        try await repo.createSession(session)
        if withJournal {
            let writer = try await journal.openWriter(session: session.id, source: .mic, startingSample: 0)
            for chunk in RecoveryTestSupport.chunks(2) { await writer.append(chunk) }
            _ = await writer.close()
        }
        return (repo, journal, session)
    }

    func testMissingAudioIsReportedAndJournalNeverDeleted() async throws {
        let fixture = try await fixture()
        let missing = MissingAudioJournal(fixture.journal)
        let engine = RecoveryTestSupport.engine(repository: fixture.repo, journals: missing,
                                                recognizer: FakeSpeechRecognizer(), root: root)
        let report = await engine.recover()
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.recovered, 0)
        XCTAssertTrue(report.needsUserAction.contains { $0.reason == "unreadable-journal" },
                      "missing audio must be an explicit user action")
        let samples = await fixture.journal.sampleCount(session: fixture.session.id, source: .mic)
        let status = try? await fixture.repo.session(fixture.session.id)?.status
        XCTAssertEqual(samples, 3_200)
        XCTAssertEqual(status, .recording)

        let retry = RecoveryTestSupport.engine(
            repository: fixture.repo, journals: fixture.journal,
            recognizer: FakeSpeechRecognizer(script: ["restored"], samplesPerSegment: 1_600), root: root)
        let healed = await retry.recover()
        XCTAssertEqual(healed.recovered, 1)
    }

    func testStaleLockFromKilledOwnerIsBrokenDuringRecovery() async throws {
        let fixture = try await fixture()
        let dead = RecoveryLockOwner(pid: 999_999, acquiredAt: Date(), heartbeatAt: Date())
        let abandoned = RecoveryLock(root: root.appendingPathComponent("Locks", isDirectory: true),
                                     session: fixture.session.id, owner: dead)
        try abandoned.acquire()
        let engine = RecoveryTestSupport.engine(repository: fixture.repo, journals: fixture.journal,
                                                recognizer: FakeSpeechRecognizer(script: ["ok"],
                                                                                 samplesPerSegment: 1_600),
                                                root: root)
        let report = await engine.recover()
        XCTAssertEqual(report.recovered, 1, "a stale lock from a killed process must not block recovery")
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(RecoveryLock.staleEvidence(root: root.appendingPathComponent("Locks")).count, 1)
    }

    func testOrphanJournalWithoutVerifiedFinalizationIsKeptAndReported() async throws {
        let fixture = try await fixture(status: .complete)
        let engine = RecoveryTestSupport.engine(repository: fixture.repo, journals: fixture.journal,
                                                recognizer: FakeSpeechRecognizer(), root: root)
        let report = await engine.recover()
        XCTAssertEqual(report.scanned, 0)
        XCTAssertTrue(report.needsUserAction.contains { $0.reason == "orphan-journal" })
        XCTAssertTrue(report.discarded.isEmpty, "nothing may be discarded without proof")
        let remaining = await fixture.journal.sessionsWithJournals()
        XCTAssertEqual(remaining, [fixture.session.id])
    }

    func testRetentionSettingSuppressesOrphanSweep() async throws {
        let fixture = try await fixture(status: .complete)
        let engine = RecoveryTestSupport.engine(repository: fixture.repo, journals: fixture.journal,
                                                recognizer: FakeSpeechRecognizer(), root: root,
                                                keepJournals: true)
        let report = await engine.recover()
        XCTAssertFalse(report.needsUserAction.contains { $0.reason == "orphan-journal" })
        let remaining = await fixture.journal.sessionsWithJournals()
        XCTAssertEqual(remaining, [fixture.session.id])
    }

    func testDamagedLedgerRecordIsQuarantinedAndRecoveryStillWorks() async throws {
        let fixture = try await fixture()
        let ledger = RecoveryLedger(root: root.appendingPathComponent("State"))
        try await ledger.append(RecoveryLedgerRecord(id: "prior", kind: .started,
                                                     session: fixture.session.id.value))
        let dir = root.appendingPathComponent("State/Records", isDirectory: true)
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        var data = try Data(contentsOf: file)
        data[data.count - 1] ^= 0x3F
        try data.write(to: file)

        let engine = RecoveryTestSupport.engine(repository: fixture.repo, journals: fixture.journal,
                                                recognizer: FakeSpeechRecognizer(script: ["clean"],
                                                                                 samplesPerSegment: 1_600),
                                                root: root)
        let report = await engine.recover()
        XCTAssertEqual(report.recovered, 1)
        XCTAssertEqual(report.integrity.corrupt, 1)
        XCTAssertEqual(report.integrity.quarantined, 1)
        XCTAssertEqual(report.quarantinedFiles.count, 1)
        XCTAssertFalse(report.integrity.isClean)
    }
}
