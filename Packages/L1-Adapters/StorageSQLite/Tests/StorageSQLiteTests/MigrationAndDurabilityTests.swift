import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowStorageSQLite

final class MigrationAndDurabilityTests: XCTestCase {
    func testFullDiskErrorExplainsHowToRecover() {
        // The reproduced failure: a missing -shm on a full volume makes
        // SQLite report code 10 "disk I/O error" with IOERR_SHMOPEN (4618)
        // and ENOSPC in the system code.
        let error = SQLiteError(code: 10, message: "disk I/O error", sql: "PRAGMA journal_mode=WAL",
                                extendedCode: 4618, systemCode: 28)
        XCTAssertTrue(error.isDiskFull)
        XCTAssertTrue(error.localizedDescription.contains("Not enough disk space"))
        XCTAssertTrue(error.localizedDescription.contains("Free some space and try again"))
        XCTAssertTrue(error.localizedDescription.contains("extended 4618, system 28"))
    }

    func testPreflightRefusesFullVolumeWithoutTouchingDatabase() throws {
        let url = databaseURL()
        try Data("existing database bytes".utf8).write(to: url)
        let before = try Data(contentsOf: url)

        XCTAssertThrowsError(try SQLiteStoreFactory.open(url: url, minimumFreeBytes: .max)) { error in
            XCTAssertEqual((error as? SQLiteError)?.isDiskFull, true)
            XCTAssertTrue(error.localizedDescription.contains("Not enough disk space"))
        }
        XCTAssertEqual(try Data(contentsOf: url), before, "a refused open must not rewrite the database")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.filter { $0.hasPrefix(".superflow-space-probe") }, [],
                       "the space probe must clean up after itself")
        XCTAssertFalse(files.contains { $0.contains("corrupt") || $0.contains("recovered") })
    }

    func testFullVolumeReportsDiskSpaceInsteadOfSQLiteIOError() async throws {
        try await withTinyVolume { mount in
            let url = mount.appendingPathComponent("Superflow.sqlite")
            do {
                let store = try SQLiteStoreFactory.open(url: url)
                try await store.createSession(SessionRecord(id: SessionID("kept"),
                                                            kind: .dictation,
                                                            modelProfile: ModelProfile.default.id))
            }
            let committed = try Data(contentsOf: url)
            XCTAssertTrue(try fillVolume(mount), "the test image should reach ENOSPC")

            XCTAssertThrowsError(try SQLiteStoreFactory.open(url: url)) { error in
                XCTAssertEqual((error as? SQLiteError)?.isDiskFull, true)
                XCTAssertFalse(error.localizedDescription.contains("SQLite 10:"),
                               "a full volume must not surface as an opaque disk I/O error")
            }
            XCTAssertEqual(try Data(contentsOf: url), committed,
                           "a refused open must leave the committed database intact")

            for file in try FileManager.default.contentsOfDirectory(atPath: mount.path)
            where file.hasPrefix("fill-") {
                try FileManager.default.removeItem(at: mount.appendingPathComponent(file))
            }
            let reopened = try SQLiteStoreFactory.open(url: url)
            let session = try await reopened.session(SessionID("kept"))
            XCTAssertNotNil(session, "committed rows must survive the disk-space refusal")
        }
    }

    private func withTinyVolume(_ body: (URL) async throws -> Void) async throws {
        let image = directory.appendingPathComponent("tiny.dmg")
        let mount = directory.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["create", "-size", "64m", "-fs", "APFS",
                                       "-volname", "SuperflowTest", "-quiet", image.path]) else {
            throw XCTSkip("hdiutil cannot create a test volume here")
        }
        guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-quiet",
                                       "-mountpoint", mount.path]) else {
            throw XCTSkip("hdiutil cannot attach a test volume here")
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
        try await body(mount)
    }

    /// Fills the volume in 1 MiB steps and then in 4 KiB steps. False means it
    /// never reached ENOSPC, so the caller's assertion would be meaningless.
    private func fillVolume(_ root: URL) throws -> Bool {
        for size in [1 << 20, 4 << 10] {
            let chunk = Data(repeating: 0, count: size)
            for index in 0..<4_000 {
                do {
                    try chunk.write(to: root.appendingPathComponent("fill-\(size)-\(index)"))
                } catch {
                    break
                }
            }
        }
        do {
            try Data(repeating: 0, count: 4_096).write(to: root.appendingPathComponent("fill-final"))
            return false
        } catch {
            return true
        }
    }

    private func run(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func databaseURL(_ name: String = "store.sqlite") -> URL {
        directory.appendingPathComponent(name)
    }

    private func fixtureSQL() throws -> String {
        guard let url = Bundle.module.url(forResource: "schema-v1", withExtension: "sql",
                                          subdirectory: "Fixtures") else {
            throw FixtureError("schema-v1.sql fixture is missing from the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func seedV1Database(at url: URL) throws {
        let connection = try SQLiteConnection(path: url.path)
        try connection.execute(try fixtureSQL())
        try connection.setUserVersion(1)
        try connection.execute("""
        INSERT INTO sessions (id, kind, started_at, status, model_profile, local_day)
        VALUES ('v1-session', 'dictation', 1700000000, 'complete', 'parakeet-eou-120m', '2023-11-14')
        """)
        try connection.execute("""
        INSERT INTO segments (session_id, idx, start_ms, end_ms, source, raw_text, created_at)
        VALUES ('v1-session', 0, 0, 1000, 'mic', 'legacy needle', 1700000000)
        """)
        try connection.execute("""
        INSERT INTO segment_search (session_id, idx, text)
        VALUES ('v1-session', 0, 'legacy needle')
        """)
    }

    private func indexNames(_ connection: SQLiteConnection, table: String) throws -> Set<String> {
        let statement = try connection.prepare("PRAGMA index_list(\(table))")
        var names = Set<String>()
        while try statement.step() {
            if let name = statement.text(1) { names.insert(name) }
        }
        return names
    }

    func testV1FixtureMigratesForwardAndKeepsRowsAndSearch() async throws {
        let url = databaseURL()
        try seedV1Database(at: url)

        let store = try SQLiteStore(path: url.path)
        let session = try await store.session(SessionID("v1-session"))
        let segments = try await store.segments(session: SessionID("v1-session"))
        let found = try await store.sessions(kind: nil, query: "legacy", limit: 10, offset: 0)
        XCTAssertEqual(session?.status, .complete)
        XCTAssertEqual(session?.localDay, "2023-11-14")
        XCTAssertEqual(segments.map(\.rawText), ["legacy needle"])
        XCTAssertEqual(found.map(\.id), [SessionID("v1-session")])

        let connection = try SQLiteConnection(path: url.path)
        XCTAssertEqual(try connection.userVersion, Schema.currentVersion)
        let sessionIndexes = try indexNames(connection, table: "sessions")
        let segmentIndexes = try indexNames(connection, table: "segments")
        XCTAssertTrue(sessionIndexes.contains("sessions_status"))
        XCTAssertTrue(segmentIndexes.contains("segments_source"))
    }

    /// v4 rebuilds a ledger that was never maintained: an old library has all its
    /// words in `sessions` while `daily_stats` says zero (or worse, negative).
    func testV3LedgerIsRebuiltFromSessions() async throws {
        let url = databaseURL("ledger.sqlite")
        do {
            let connection = try SQLiteConnection(path: url.path)
            try connection.execute(try fixtureSQL())
            try connection.setUserVersion(1)
            try connection.execute(Schema.v2)
            try connection.setUserVersion(2)
            try connection.execute(Schema.v3)
            try connection.setUserVersion(3)
            try connection.execute("""
            INSERT INTO sessions (id, kind, started_at, status, model_profile, local_day,
                                  word_count, duration_ms)
            VALUES ('d1', 'dictation', 1700000000, 'complete', 'p', '2023-11-14', 100, 60000),
                   ('d2', 'dictation', 1700000100, 'complete', 'p', '2023-11-14', 50, 30000),
                   ('d3', 'dictation', 1700000200, 'recording', 'p', '2023-11-14', 7, 5000),
                   ('m1', 'meeting', 1700000300, 'complete', 'p', '2023-11-14', 900, 600000);
            INSERT INTO daily_stats (day, words, audio_ms, sessions)
            VALUES ('2023-11-14', 0, 0, -1);
            """)
        }

        let store = try SQLiteStore(path: url.path)
        let stats = try await store.dailyStats(fromDay: "2023-11-14", toDay: "2023-11-14")
        XCTAssertEqual(stats, [DailyStat(day: "2023-11-14", words: 150,
                                         audioMs: 90_000, sessions: 2)])
        let connection = try SQLiteConnection(path: url.path)
        XCTAssertEqual(try connection.userVersion, Schema.currentVersion)
    }

    func testMigrationIsIdempotentAcrossReopen() async throws {
        let url = databaseURL()
        try seedV1Database(at: url)
        do {
            let first = try SQLiteStore(path: url.path)
            let count = try await first.sessionCount(kind: nil)
            XCTAssertEqual(count, 1)
        }
        let second = try SQLiteStore(path: url.path)
        let count = try await second.sessionCount(kind: nil)
        XCTAssertEqual(count, 1)
        let connection = try SQLiteConnection(path: url.path)
        XCTAssertEqual(try connection.userVersion, Schema.currentVersion)
    }

    func testFailedMigrationRollsBackAndFactoryPreservesHistory() async throws {
        let url = databaseURL("blocked.sqlite")
        do {
            let connection = try SQLiteConnection(path: url.path)
            try connection.execute(try fixtureSQL())
            try connection.setUserVersion(1)
            try connection.execute("CREATE TABLE sessions_status (value INTEGER)")
        }

        XCTAssertThrowsError(try SQLiteStore(path: url.path))
        let afterFailure = try SQLiteConnection(path: url.path)
        XCTAssertEqual(try afterFailure.userVersion, 1, "failed v2 migration must not advance user_version")
        let blocked = try afterFailure.scalarText(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions_status'")
        XCTAssertEqual(blocked, "sessions_status")

        XCTAssertThrowsError(try SQLiteStoreFactory.open(url: url))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.contains("Superflow-corrupt") })
        XCTAssertEqual(try afterFailure.scalarInt("SELECT COUNT(*) FROM sessions"), 0)

    }

    func testFactoryCreatesMissingParentDirectory() async throws {
        let url = directory.appendingPathComponent("missing/nested/store.sqlite")
        let store = try SQLiteStoreFactory.open(url: url)
        let count = try await store.sessionCount(kind: nil)
        XCTAssertEqual(count, 0)
    }

    func testBusyMigrationMustNeverQuarantineDatabase() throws {
        let url = databaseURL()
        try seedV1Database(at: url)
        let writer = try SQLiteConnection(path: url.path)
        try writer.execute("BEGIN IMMEDIATE")
        defer { try? writer.execute("ROLLBACK") }
        XCTAssertThrowsError(try SQLiteStoreFactory.open(url: url))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.contains("Superflow-corrupt") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func seedCheckpointedHistory(at url: URL) throws {
        let connection = try SQLiteConnection(path: url.path)
        try Schema.migrate(connection)
        try connection.execute("""
        INSERT INTO sessions (id, kind, started_at, status, model_profile, local_day)
        VALUES ('preserved', 'dictation', 1700000000, 'complete', 'test', '2023-11-14')
        """)
        try connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try connection.execute("PRAGMA journal_mode=DELETE")
        XCTAssertEqual(try connection.scalarText("PRAGMA journal_mode"), "delete")
    }

    func testStaleSidecarsPreserveCommittedHistory() async throws {
        let url = databaseURL()
        try seedCheckpointedHistory(at: url)
        try Data(repeating: 0, count: 32768).write(to: URL(fileURLWithPath: url.path + "-shm"))
        try Data().write(to: URL(fileURLWithPath: url.path + "-wal"))
        let reopened = try SQLiteStoreFactory.open(url: url)
        let session = try await reopened.session(SessionID("preserved"))
        XCTAssertNotNil(session)
    }

    func testSQLiteReconstructsStaleSharedMemoryWithoutQuarantine() async throws {
        let url = databaseURL()
        try seedCheckpointedHistory(at: url)
        let sharedMemory = URL(fileURLWithPath: url.path + "-shm")
        if FileManager.default.fileExists(atPath: sharedMemory.path) {
            try FileManager.default.removeItem(at: sharedMemory)
        }
        try FileManager.default.createDirectory(at: sharedMemory, withIntermediateDirectories: true)
        let reopened = try SQLiteStoreFactory.open(url: url)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.contains("Superflow-corrupt") })
        let session = try await reopened.session(SessionID("preserved"))
        XCTAssertNotNil(session)
    }

    func testConcurrentFactoryOpensShareCommittedHistory() async throws {
        let url = databaseURL()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<2 {
                group.addTask {
                    let store = try SQLiteStoreFactory.open(url: url)
                    try await store.createSession(SessionRecord(id: SessionID("concurrent-\(index)"),
                                                                kind: .dictation,
                                                                modelProfile: ModelProfile.default.id))
                }
            }
            try await group.waitForAll()
        }
        let reopened = try SQLiteStoreFactory.open(url: url)
        let count = try await reopened.sessionCount(kind: nil)
        XCTAssertEqual(count, 2)
    }

    func testWALAndRuntimePragmasAreEnabled() throws {
        let url = databaseURL()
        let store = try SQLiteStore(path: url.path)
        let connection = try SQLiteConnection(path: store.path)
        let journalMode = try connection.scalarText("PRAGMA journal_mode")
        let synchronous = try connection.scalarInt("PRAGMA synchronous")
        let foreignKeys = try connection.scalarInt("PRAGMA foreign_keys")
        let busyTimeout = try connection.scalarInt("PRAGMA busy_timeout")
        XCTAssertEqual(journalMode, "wal")
        XCTAssertEqual(synchronous, 1)
        XCTAssertEqual(foreignKeys, 1)
        XCTAssertEqual(busyTimeout, 5_000)
    }

    func testFTS5IndexExistsAndSpecialQueriesAreSafe() async throws {
        let store = try SQLiteStore(path: databaseURL().path)
        let session = SessionRecord(id: SessionID("fts"), kind: .dictation,
                                    modelProfile: "parakeet-eou-120m")
        try await store.createSession(session)
        try await store.appendSegment(Segment(sessionID: session.id, index: 0, startMs: 0,
                                              endMs: 100, rawText: "quarterly roadmap review"))
        let connection = try SQLiteConnection(path: store.path)
        let sql = try connection.scalarText(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='segment_search'")
        XCTAssertTrue(sql?.lowercased().contains("fts5") == true)

        let found = try await store.sessions(kind: nil, query: "roadmap", limit: 10, offset: 0)
        XCTAssertEqual(found.map(\.id), [session.id])
        let unsafe = try await store.sessions(kind: nil, query: "\"unbalanced", limit: 10, offset: 0)
        XCTAssertTrue(unsafe.isEmpty)
    }

    func testAudioMetadataRoundTripsAndClears() async throws {
        let store = try SQLiteStore(path: databaseURL().path)
        var session = SessionRecord(id: SessionID("audio"), kind: .dictation,
                                    modelProfile: ModelProfile.default.id)
        try await store.createSession(session)

        let peaks = Data([0, 64, 128, 255])
        try await store.setAudio(session: session.id, duration: 1.4, peaks: peaks)
        session = try await store.session(session.id) ?? session
        XCTAssertEqual(session.audioDuration ?? -1, 1.4, accuracy: 0.001)
        XCTAssertEqual(session.audioPeaks, peaks)

        let withAudio = try await store.sessionsWithAudio()
        XCTAssertEqual(withAudio.map(\.value), ["audio"])

        try await store.clearAudio(session: session.id)
        let cleared = try await store.session(session.id)
        XCTAssertNil(cleared?.audioDuration)
        XCTAssertNil(cleared?.audioPeaks)
        let remaining = try await store.sessionsWithAudio()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDataSurvivesRelaunch() async throws {
        let url = databaseURL()
        do {
            let store = try SQLiteStore(path: url.path)
            let session = SessionRecord(id: SessionID("persisted"), kind: .dictation,
                                        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                        status: .recording, modelProfile: "parakeet-eou-120m")
            try await store.createSession(session)
            try await store.appendSegment(Segment(sessionID: session.id, index: 0, startMs: 0,
                                                  endMs: 500, rawText: "survives relaunch"))
            var settings = AppSettings.default
            settings.displayName = "Persisted"
            await store.save(settings)
        }

        let reopened = try SQLiteStore(path: url.path)
        let session = try await reopened.session(SessionID("persisted"))
        let segments = try await reopened.segments(session: SessionID("persisted"))
        let settings = await reopened.load()
        XCTAssertEqual(session?.status, .recording)
        XCTAssertEqual(segments.map(\.rawText), ["survives relaunch"])
        XCTAssertEqual(settings.displayName, "Persisted")
    }

    func testRetentionPurgeSurvivesRelaunchAndKeepsActiveSessions() async throws {
        let url = databaseURL()
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let store = try SQLiteStore(path: url.path)
            let old = SessionRecord(id: SessionID("old"), kind: .dictation,
                                    startedAt: cutoff.addingTimeInterval(-10_000),
                                    status: .complete, modelProfile: "parakeet-eou-120m")
            let recent = SessionRecord(id: SessionID("recent"), kind: .dictation,
                                       startedAt: cutoff.addingTimeInterval(10_000),
                                       status: .complete, modelProfile: "parakeet-eou-120m")
            let active = SessionRecord(id: SessionID("active"), kind: .dictation,
                                       startedAt: cutoff.addingTimeInterval(-10_000),
                                       status: .recording, modelProfile: "parakeet-eou-120m")
            for session in [old, recent, active] { try await store.createSession(session) }
            let removed = try await store.purge(olderThan: cutoff)
            XCTAssertEqual(removed, 1)
        }

        let reopened = try SQLiteStore(path: url.path)
        let old = try await reopened.session(SessionID("old"))
        let recent = try await reopened.session(SessionID("recent"))
        let active = try await reopened.session(SessionID("active"))
        XCTAssertNil(old)
        XCTAssertNotNil(recent)
        XCTAssertNotNil(active)
    }

    func testFactoryPreservesCorruptDatabaseAndSidecars() throws {
        let url = databaseURL("corrupt.sqlite")
        try Data("not a sqlite database".utf8).write(to: url)
        try Data("not a wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("not a shm".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))

        XCTAssertThrowsError(try SQLiteStoreFactory.open(url: url))
        XCTAssertEqual(try Data(contentsOf: url), Data("not a sqlite database".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: url.path + "-wal")), Data("not a wal".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: url.path + "-shm")), Data("not a shm".utf8))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.contains("Superflow-corrupt") })
    }
}

private struct FixtureError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
