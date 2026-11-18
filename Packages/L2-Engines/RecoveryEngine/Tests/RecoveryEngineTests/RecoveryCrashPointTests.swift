import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowRecoveryEngine

/// Drives the engine against real files in a temp directory. For every named stage the first run is
/// killed by a fault injector; a brand-new engine then restarts over the exact on-disk state and
/// must finish with no lost or duplicated transcript data.
final class RecoveryCrashPointTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws { root = RecoveryTestSupport.tempRoot("crash") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    actor FaultGate {
        private let target: RecoveryStage
        private let occurrence: Int
        private(set) var fired = false
        init(_ target: RecoveryStage, occurrence: Int = 1) {
            self.target = target
            self.occurrence = occurrence
        }
        func shouldFire(_ stage: RecoveryStage, _ count: Int) -> Bool {
            guard !fired, stage == target, count == occurrence else { return false }
            fired = true
            return true
        }
        var didFire: Bool { fired }
    }

    private struct Fixture {
        let root: URL
        let repository: InMemoryRepository
        let journal: FileBackedJournalStore
        let session: SessionRecord
        let recognizer: FakeSpeechRecognizer
    }

    private func makeFixture(text: String = "recovered αβ 日本語 🎙️") async throws -> Fixture {
        let repository = InMemoryRepository()
        let journal = FileBackedJournalStore(root: root.appendingPathComponent("Journals", isDirectory: true))
        let session = SessionRecord(kind: .dictation, status: .recording,
                                    modelProfile: ModelProfile.default.id)
        try await repository.createSession(session)
        try await repository.appendSegment(Segment(
            sessionID: session.id, index: 0, startMs: 0, endMs: 100,
            source: .mic, rawText: "committed before crash"))
        let writer = try await journal.openWriter(session: session.id, source: .mic, startingSample: 0)
        for chunk in RecoveryTestSupport.chunks(3) { await writer.append(chunk) }
        _ = await writer.close()
        let recognizer = FakeSpeechRecognizer(script: [text], samplesPerSegment: 1_600)
        return Fixture(root: root, repository: repository, journal: journal,
                       session: session, recognizer: recognizer)
    }

    private func assertHealed(_ fixture: Fixture, text: String,
                              reports: [RecoveryReport], context: String = "",
                              file: StaticString = #filePath, line: UInt = #line) async {
        let rows = try? await fixture.repository.segments(session: fixture.session.id)
        let segments = rows ?? []
        XCTAssertGreaterThanOrEqual(segments.count, 1, file: file, line: line)
        XCTAssertEqual(segments.first?.rawText, "committed before crash", file: file, line: line)
        let keys = segments.map { "\($0.source.rawValue):\($0.startMs):\($0.endMs)" }
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate segments after restart", file: file, line: line)
        XCTAssertEqual(segments.map(\.index), Array(0..<segments.count), file: file, line: line)
        XCTAssertTrue(segments.contains { $0.rawText.contains(text) },
                      "\(context) recovered text missing: \(segments.map(\.rawText))", file: file, line: line)
        let final = try? await fixture.repository.session(fixture.session.id)
        XCTAssertEqual(final?.status, .recovered, "\(context) session status", file: file, line: line)
        let remaining = await fixture.journal.sessionsWithJournals()
        XCTAssertTrue(remaining.isEmpty,
                      "\(context) journal was not disposed of: \(remaining.map(\.value))", file: file, line: line)
        XCTAssertTrue(reports.contains { $0.discarded.contains { $0.sessionID == fixture.session.id } },
                      "\(context) journal disposal must be reported", file: file, line: line)
        XCTAssertTrue(reports.last?.integrity.isClean ?? false, file: file, line: line)
        let stateFiles = try? FileManager.default.contentsOfDirectory(
            at: fixture.root.appendingPathComponent("State/Records", isDirectory: true),
            includingPropertiesForKeys: nil)
        XCTAssertFalse((stateFiles ?? []).contains { $0.pathExtension == "tmp" }, file: file, line: line)
    }

    /// N crash points over the full recovery pipeline, each with a fresh ephemeral store.
    func testCrashAtEveryRecoveryStageThenRestartHealsWithoutLoss() async throws {
        let text = "recovered αβ 日本語 🎙️"
        for stage in RecoveryStage.allCases {
            root = RecoveryTestSupport.tempRoot("crash-\(stage.rawValue)")
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try await makeFixture(text: text)
            let gate = FaultGate(stage)
            let first = RecoveryTestSupport.engine(
                repository: fixture.repository, journals: fixture.journal,
                recognizer: fixture.recognizer, root: root,
                cleaner: { text in RecoveryCleaned(text: text, state: .pending) },
                fault: { s, n in await gate.shouldFire(s, n) })
            let before = await first.recover()
            let fired = await gate.didFire
            XCTAssertTrue(fired, "\(stage): fault never reached")
            XCTAssertGreaterThan(before.failed, 0, "\(stage): crash must be reported")
            XCTAssertFalse(before.needsUserAction.isEmpty, "\(stage): crash needs user action")

            let restartedJournal = FileBackedJournalStore(
                root: root.appendingPathComponent("Journals", isDirectory: true))
            let second = RecoveryTestSupport.engine(
                repository: fixture.repository, journals: restartedJournal,
                recognizer: FakeSpeechRecognizer(script: [text], samplesPerSegment: 1_600), root: root)
            let after = await second.recover()
            XCTAssertEqual(after.failed, 0, "\(stage): restart failed: \(after.notices)")
            await assertHealed(fixture, text: text, reports: [before, after], context: "[\(stage)]")
        }
    }

    /// Crash *after* the first recovered row was committed exercises the dedupe path on restart.
    func testCrashAfterFirstSegmentCommittedDoesNotDuplicateOnRestart() async throws {
        let fixture = try await makeFixture()
        let gate = FaultGate(.appendSegment, occurrence: 2)
        let first = RecoveryTestSupport.engine(
            repository: fixture.repository, journals: fixture.journal,
            recognizer: fixture.recognizer, root: root,
            fault: { s, n in await gate.shouldFire(s, n) })
        let before = await first.recover()
        let rowsAfterCrash = try await fixture.repository.segments(session: fixture.session.id)
        XCTAssertEqual(rowsAfterCrash.count, 2, "the first recovered row must be committed before the crash")
        let second = RecoveryTestSupport.engine(
            repository: fixture.repository, journals: fixture.journal,
            recognizer: FakeSpeechRecognizer(script: ["recovered αβ 日本語 🎙️"], samplesPerSegment: 1_600),
            root: root)
        let after = await second.recover()
        XCTAssertEqual(after.failed, 0)
        await assertHealed(fixture, text: "recovered αβ 日本語 🎙️", reports: [before, after])
    }

    func testDiskFullDuringAppendKeepsJournalAndRetrySucceeds() async throws {
        let fixture = try await makeFixture()
        await fixture.repository.setFailure(.append)
        let failing = RecoveryTestSupport.engine(repository: fixture.repository, journals: fixture.journal,
                                                 recognizer: fixture.recognizer, root: root)
        let before = await failing.recover()
        let samplesBefore = await fixture.journal.sampleCount(session: fixture.session.id, source: .mic)
        let statusBefore = try? await fixture.repository.session(fixture.session.id)?.status
        XCTAssertEqual(before.failed, 1)
        XCTAssertEqual(before.recovered, 0)
        XCTAssertEqual(samplesBefore, 4_800)
        XCTAssertEqual(statusBefore, .recording)

        await fixture.repository.setFailure(nil)
        let retry = RecoveryTestSupport.engine(repository: fixture.repository, journals: fixture.journal,
                                               recognizer: FakeSpeechRecognizer(script: ["retry words"],
                                                                                samplesPerSegment: 1_600),
                                               root: root)
        let after = await retry.recover()
        XCTAssertEqual(after.failed, 0)
        XCTAssertEqual(after.recovered, 1)
        XCTAssertGreaterThan(after.segmentsAdded, 0,
                             "retry added no rows: replayed=\(after.samplesReplayed) notices=\(after.notices)")
        await assertHealed(fixture, text: "retry words", reports: [before, after], context: "[disk-full]")
    }

    func testRepeatedRecoveryIsIdempotent() async throws {
        let fixture = try await makeFixture()
        let engine = RecoveryTestSupport.engine(repository: fixture.repository, journals: fixture.journal,
                                                recognizer: fixture.recognizer, root: root)
        let first = await engine.recover()
        let snapshot = try await fixture.repository.segments(session: fixture.session.id)
        let second = await engine.recover()
        let third = await engine.recover()
        XCTAssertEqual(first.recovered, 1)
        XCTAssertEqual(second.scanned, 0)
        XCTAssertEqual(third.scanned, 0)
        XCTAssertEqual(second.segmentsAdded, 0)
        let after = try await fixture.repository.segments(session: fixture.session.id)
        XCTAssertEqual(after, snapshot)
        XCTAssertTrue(first.integrity.isClean)
    }

    func testConcurrentRecoveryInstancesDoNotDuplicateRows() async throws {
        let fixture = try await makeFixture()
        let firstEngine = RecoveryTestSupport.engine(repository: fixture.repository, journals: fixture.journal,
                                                     recognizer: fixture.recognizer, root: root)
        let secondEngine = RecoveryTestSupport.engine(repository: fixture.repository, journals: fixture.journal,
                                                      recognizer: fixture.recognizer, root: root)
        async let first = firstEngine.recover()
        async let second = secondEngine.recover()
        let firstReport = await first
        let secondReport = await second
        let reports = [firstReport, secondReport]
        XCTAssertEqual(reports.filter { $0.recovered == 1 }.count, 1)
        // The loser either finds the lock held, or starts after the winner has already finished.
        XCTAssertEqual(reports.filter { $0.skippedBusy == 1 || $0.scanned == 0 }.count, 1)
        let rows = try await fixture.repository.segments(session: fixture.session.id)
        let keys = rows.map { "\($0.source.rawValue):\($0.startMs):\($0.endMs)" }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testBoundedRecoveryTimeKeepsJournalForRetry() async throws {
        let fixture = try await makeFixture()
        let clock = ManualTimeSource()
        let gate = FaultGate(.replayChunk)
        let slow = RecoveryTestSupport.engine(
            repository: fixture.repository, journals: fixture.journal,
            recognizer: fixture.recognizer, root: root, clock: clock, budget: .seconds(1),
            fault: { stage, count in
                if await gate.shouldFire(stage, count) { clock.advance(ms: 60_000) }
                return false
            })
        let before = await slow.recover()
        let statusBefore = try? await fixture.repository.session(fixture.session.id)?.status
        let samplesBefore = await fixture.journal.sampleCount(session: fixture.session.id, source: .mic)
        XCTAssertEqual(before.failed, 1)
        XCTAssertTrue(before.needsUserAction.contains { $0.reason == "recovery-timeout" })
        XCTAssertEqual(statusBefore, .recording)
        XCTAssertEqual(samplesBefore, 4_800)

        let retry = RecoveryTestSupport.engine(repository: fixture.repository, journals: fixture.journal,
                                               recognizer: FakeSpeechRecognizer(script: ["after timeout"],
                                                                                samplesPerSegment: 1_600),
                                               root: root)
        let after = await retry.recover()
        XCTAssertEqual(after.recovered, 1)
        await assertHealed(fixture, text: "after timeout", reports: [before, after], context: "[timeout]")
    }
}
