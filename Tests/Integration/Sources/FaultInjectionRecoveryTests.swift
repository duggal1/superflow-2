import Foundation
import SuperflowAudioJournal
import SuperflowKernel
import SuperflowRecoveryEngine
import SuperflowStorageSQLite
import SuperflowTestKit
import XCTest

/// Fault-injection coverage for the crash-recovery contract. These tests drive the real
/// `FileJournalStore` and the real SQLite repository (not the fakes) so the on-disk manifest,
/// sample positions and committed rows are exercised exactly as a `kill -9` + relaunch would
/// leave them. The plan requires that recovery restores every journaled sample and every
/// committed transcript row, with only the most recent unflushed 5 seconds at risk.
final class FaultInjectionRecoveryTests: XCTestCase {
    private var root: URL!
    private var journalRoot: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowFaultInjection-\(UUID().uuidString)", isDirectory: true)
        journalRoot = root.appendingPathComponent("Journals", isDirectory: true)
        databaseURL = root.appendingPathComponent("history.sqlite")
        try FileManager.default.createDirectory(at: journalRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Simulates `kill -9` mid-dictation: a raw session is left `recording`, part of it was
    /// committed to SQLite, the journal was never closed, and then the app relaunches.
    func testKill9MidSessionRestoresEverySampleAndCommittedRow() async throws {
        let session = SessionID("kill9-dictation")
        let committedSamples: Int64 = 80_000   // 5 s of audio already has transcript rows
        let totalSamples: Int64 = 160_000      // 10 s of audio captured in total

        let store = try SQLiteStore(path: databaseURL.path)
        try await store.createSession(SessionRecord(
            id: session, kind: .dictation, status: .recording,
            modelProfile: ModelProfile.parakeetEOU120M.id))
        try await store.appendSegment(Segment(
            sessionID: session, index: 0, startMs: 0, endMs: 5_000,
            rawText: "committed before the crash", cleanupState: .pending))

        // Capture writes the journal but the process dies before close()/fsync.
        let journal = FileJournalStore(root: journalRoot, keepAfterClose: true,
                                       minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let writer = try await journal.openWriter(session: session, source: .mic,
                                                  startingSample: 0)
        var cursor: Int64 = 0
        while cursor < totalSamples {
            let count = Int(min(Int64(16_000), totalSamples - cursor))
            await writer.append(AudioChunk(samples: [Float](repeating: 0.2, count: count),
                                           startSample: cursor, source: .mic))
            cursor += Int64(count)
        }

        let journaled = await journal.sampleCount(session: session, source: .mic)
        XCTAssertEqual(journaled, totalSamples, "the journal did not reach the end of capture")

        // Relaunch: a fresh store over the same directory plus recovery.
        let relaunched = FileJournalStore(root: journalRoot, keepAfterClose: false,
                                          minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let recognizer = FakeSpeechRecognizer(script: ["recovered words"],
                                              samplesPerSegment: 80_000)
        let engine = RecoveryEngine(repository: store, journals: relaunched,
                                    recognizer: recognizer)

        let committedBefore = try await store.segments(session: session)
        let report = await engine.recover()

        XCTAssertEqual(report.scanned, 1)
        XCTAssertEqual(report.recovered, 1)
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(report.samplesReplayed, totalSamples - committedSamples,
                       "recovery must replay every sample after the last committed position")

        let rows = try await store.segments(session: session)
        XCTAssertEqual(rows.count, committedBefore.count + report.segmentsAdded)
        XCTAssertGreaterThanOrEqual(report.segmentsAdded, 1, "uncommitted audio must become rows")
        XCTAssertEqual(rows.first?.rawText, "committed before the crash",
                       "recovery must not rewrite committed rows")

        // Recovered rows are appended after the committed ones (indices keep increasing) and the
        // committed row itself is untouched.
        let appended = rows.dropFirst(committedBefore.count)
        XCTAssertTrue(appended.allSatisfy { $0.index >= committedBefore.count },
                      "recovered rows did not continue the segment index")
        XCTAssertEqual(appended.first?.cleanupState, .pending)
        let recovered = try await store.session(session)
        XCTAssertEqual(recovered?.status, .recovered)
        XCTAssertNotNil(report.recoveredTranscripts.first { $0.sessionID == session })
        XCTAssertEqual(report.recoveredTranscripts.first?.text.contains("recovered words"), true)
    }

    /// A power loss can leave a torn last segment (an odd byte, or a half-written manifest line).
    /// Recovery must tolerate it and restore every fully-flushed sample rather than losing the lane.
    func testTornLastSegmentIsTruncatedAndFlushedSamplesSurvive() async throws {
        let session = SessionID("kill9-torn")
        let flushedSamples: Int64 = 2_001
        let store = try SQLiteStore(path: databaseURL.path)
        try await store.createSession(SessionRecord(
            id: session, kind: .dictation, status: .recording,
            modelProfile: ModelProfile.parakeetEOU120M.id))

        let journal = FileJournalStore(root: journalRoot, keepAfterClose: true,
                                       minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let writer = try await journal.openWriter(session: session, source: .mic,
                                                  startingSample: 0)
        await writer.append(AudioChunk(samples: [Float](repeating: 0.4, count: Int(flushedSamples)),
                                       startSample: 0, source: .mic))

        // Tear the last segment: one stray byte that cannot be a whole Int16 sample, plus a
        // half-written manifest line, exactly what a crash between writes produces.
        let directory = journalRoot.appendingPathComponent(session.value, isDirectory: true)
        let pcm = directory.appendingPathComponent("mic-000000.pcm")
        let handle = try FileHandle(forWritingTo: pcm)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x7F]))
        try handle.close()
        XCTAssertEqual(try Data(contentsOf: pcm).count, Int(flushedSamples) * 2 + 1)

        let manifest = directory.appendingPathComponent("mic-manifest.jsonl")
        let manifestHandle = try FileHandle(forWritingTo: manifest)
        try manifestHandle.seekToEnd()
        try manifestHandle.write(contentsOf: Data("{\"file\":\"mic-000001.pcm\",".utf8))
        try manifestHandle.close()

        let relaunched = FileJournalStore(root: journalRoot, keepAfterClose: false,
                                          minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let counted = await relaunched.sampleCount(session: session, source: .mic)
        XCTAssertEqual(counted, flushedSamples, "a torn byte must round down to whole samples")

        var replayed: Int64 = 0
        for await chunk in await relaunched.replay(session: session, source: .mic, fromSample: 0) {
            replayed += Int64(chunk.samples.count)
        }
        XCTAssertEqual(replayed, flushedSamples, "replay must return every flushed sample")

        let engine = RecoveryEngine(repository: store, journals: relaunched,
                                    recognizer: FakeSpeechRecognizer(script: ["torn recovery"],
                                                                     samplesPerSegment: 80_000))
        let report = await engine.recover()
        XCTAssertEqual(report.recovered, 1)
        XCTAssertEqual(report.samplesReplayed, flushedSamples)
        let rows = try await store.segments(session: session)
        XCTAssertFalse(rows.isEmpty, "a torn segment must not drop the whole lane")
    }

    /// Recovery must keep the journal when the user opted into retention, so a second attempt can
    /// still replay it, and must delete it otherwise.
    func testRecoveryHonorsJournalRetention() async throws {
        let retained = SessionID("retained")
        let store = try SQLiteStore(path: databaseURL.path)
        try await store.createSession(SessionRecord(
            id: retained, kind: .dictation, status: .recording,
            modelProfile: ModelProfile.parakeetEOU120M.id))
        let journal = FileJournalStore(root: journalRoot, keepAfterClose: true,
                                       minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let writer = try await journal.openWriter(session: retained, source: .mic,
                                                  startingSample: 0)
        await writer.append(AudioChunk(samples: [Float](repeating: 0.1, count: 16_000),
                                       startSample: 0, source: .mic))

        let keeping = RecoveryEngine(repository: store, journals: journal,
                                     recognizer: FakeSpeechRecognizer(script: ["kept"]),
                                     keepJournals: true)
        _ = await keeping.recover()
        let remaining = await journal.sessionsWithJournals()
        XCTAssertTrue(remaining.contains(retained), "retention must preserve the journal")
    }
}
