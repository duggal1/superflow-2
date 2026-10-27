import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowStorageSQLite

final class SQLiteStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SQLiteStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-sqlite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try SQLiteStore(path: directory.appendingPathComponent("test.sqlite").path)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSession(_ id: SessionID = SessionID("s1"), kind: SessionKind = .dictation,
                             startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                             status: SessionStatus = .recording) -> SessionRecord {
        SessionRecord(id: id, kind: kind, startedAt: startedAt, status: status,
                      frontmostBundleID: "com.apple.TextEdit", modelProfile: "parakeet-eou-120m")
    }

    func testCreateFetchAndFinalizeSession() async throws {
        let session = makeSession()
        try await store.createSession(session)
        let fetched = try await store.session(session.id)
        XCTAssertEqual(fetched?.id, session.id)
        XCTAssertEqual(fetched?.kind, .dictation)
        XCTAssertEqual(fetched?.status, .recording)
        XCTAssertEqual(fetched?.frontmostBundleID, "com.apple.TextEdit")

        try await store.finalizeSession(session.id, endedAt: Date(timeIntervalSince1970: 1_700_000_100),
                                        status: .complete, durationMs: 100_000, wordCount: 240,
                                        cleanupState: .cleaned)
        let final = try await store.session(session.id)
        XCTAssertEqual(final?.status, .complete)
        XCTAssertEqual(final?.wordCount, 240)
        XCTAssertEqual(final?.cleanupState, .cleaned)
        XCTAssertEqual(final?.durationMs, 100_000)
    }

    func testSegmentsRoundTripAndCleanedUpdate() async throws {
        let session = makeSession()
        try await store.createSession(session)
        let segment = Segment(sessionID: session.id, index: 0, startMs: 0, endMs: 1_500,
                              speakerID: "self", source: .mic, rawText: "hello world")
        try await store.appendSegment(segment)
        var stored = try await store.segments(session: session.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].rawText, "hello world")
        XCTAssertNil(stored[0].cleanedText)

        try await store.updateCleaned(session: session.id, index: 0, cleaned: "Hello, world.",
                                      state: .cleaned)
        stored = try await store.segments(session: session.id)
        XCTAssertEqual(stored[0].cleanedText, "Hello, world.")
        XCTAssertEqual(stored[0].cleanupState, .cleaned)
        XCTAssertEqual(stored[0].bestText, "Hello, world.")
    }

    func testSegmentUpsertDoesNotDuplicate() async throws {
        let session = makeSession()
        try await store.createSession(session)
        var segment = Segment(sessionID: session.id, index: 3, startMs: 10, endMs: 20,
                              rawText: "first")
        try await store.appendSegment(segment)
        segment.rawText = "second"
        try await store.appendSegment(segment)
        let stored = try await store.segments(session: session.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].rawText, "second")
    }

    func testSearchFindsSessionByCleanedText() async throws {
        let first = makeSession(SessionID("first"), startedAt: Date(timeIntervalSince1970: 100))
        let second = makeSession(SessionID("second"), startedAt: Date(timeIntervalSince1970: 200))
        try await store.createSession(first)
        try await store.createSession(second)
        try await store.appendSegment(Segment(sessionID: first.id, index: 0, startMs: 0, endMs: 10,
                                              rawText: "quarterly roadmap review"))
        try await store.appendSegment(Segment(sessionID: second.id, index: 0, startMs: 0, endMs: 10,
                                              rawText: "grocery list"))

        let matches = try await store.sessions(kind: nil, query: "roadmap", limit: 20, offset: 0)
        XCTAssertEqual(matches.map(\.id), [first.id])

        try await store.updateCleaned(session: first.id, index: 0, cleaned: "Quarterly roadmap review.",
                                      state: .cleaned)
        let cleaned = try await store.sessions(kind: nil, query: "Quarterly", limit: 20, offset: 0)
        XCTAssertEqual(cleaned.map(\.id), [first.id])

        try await store.updateCleaned(session: first.id, index: 0, cleaned: "Strategy offsite",
                                      state: .cleaned)
        let stale = try await store.sessions(kind: nil, query: "roadmap", limit: 20, offset: 0)
        XCTAssertTrue(stale.isEmpty)
    }

    func testSearchMatchesTitleAndKindFilter() async throws {
        var meeting = makeSession(SessionID("meeting"), kind: .meeting)
        meeting.title = "Design critique"
        try await store.createSession(meeting)
        let byTitle = try await store.sessions(kind: .meeting, query: "critique", limit: 10, offset: 0)
        XCTAssertEqual(byTitle.map(\.id), [meeting.id])
        let wrongKind = try await store.sessions(kind: .dictation, query: "critique", limit: 10, offset: 0)
        XCTAssertTrue(wrongKind.isEmpty)
    }

    func testPaginationAndCounts() async throws {
        for i in 0..<5 {
            let session = makeSession(SessionID("s\(i)"),
                                      startedAt: Date(timeIntervalSince1970: Double(100 + i)))
            try await store.createSession(session)
        }
        let page = try await store.sessions(kind: nil, query: nil, limit: 2, offset: 1)
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page[0].id, SessionID("s3"))
        let total = try await store.sessionCount(kind: nil)
        let meetings = try await store.sessionCount(kind: .meeting)
        XCTAssertEqual(total, 5)
        XCTAssertEqual(meetings, 0)
    }

    func testSpeakersAndRename() async throws {
        let session = makeSession()
        try await store.createSession(session)
        try await store.upsertSpeaker(SpeakerRecord(sessionID: session.id, id: "remote-1",
                                                    label: "Speaker 1", isSelf: false))
        try await store.upsertSpeaker(SpeakerRecord(sessionID: session.id, id: "self",
                                                    label: "You", isSelf: true))
        var speakers = try await store.speakers(session: session.id)
        XCTAssertEqual(speakers.count, 2)

        try await store.renameSpeaker(session: session.id, id: "remote-1", label: "Priya")
        speakers = try await store.speakers(session: session.id)
        XCTAssertEqual(speakers.first { $0.id == "remote-1" }?.label, "Priya")
    }

    func testDailyStatsAccumulate() async throws {
        try await store.addDailyStat(DailyStat(day: "2026-01-01", words: 100, audioMs: 1_000, sessions: 1))
        try await store.addDailyStat(DailyStat(day: "2026-01-01", words: 50, audioMs: 500, sessions: 1))
        try await store.addDailyStat(DailyStat(day: "2026-01-02", words: 10, audioMs: 100, sessions: 1))
        let stats = try await store.dailyStats(fromDay: "2026-01-01", toDay: "2026-01-02")
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].words, 150)
        XCTAssertEqual(stats[0].audioMs, 1_500)
        XCTAssertEqual(stats[0].sessions, 2)
        XCTAssertEqual(stats[1].words, 10)
    }

    func testUnfinishedAndPurge() async throws {
        let active = makeSession(SessionID("active"), startedAt: Date(timeIntervalSince1970: 100),
                                 status: .recording)
        let old = makeSession(SessionID("old"), startedAt: Date(timeIntervalSince1970: 200),
                              status: .complete)
        let recent = makeSession(SessionID("recent"), startedAt: Date(timeIntervalSince1970: 1_000),
                                 status: .complete)
        for session in [active, old, recent] { try await store.createSession(session) }
        try await store.appendSegment(Segment(sessionID: old.id, index: 0, startMs: 0, endMs: 1,
                                              rawText: "old words"))

        let unfinished = try await store.unfinishedSessions()
        XCTAssertEqual(unfinished.map(\.id), [active.id])

        let purged = try await store.purge(olderThan: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(purged, 1)
        let oldAfter = try await store.session(old.id)
        let recentAfter = try await store.session(recent.id)
        let activeAfter = try await store.session(active.id)
        XCTAssertNil(oldAfter)
        XCTAssertNotNil(recentAfter)
        XCTAssertNotNil(activeAfter)
        let search = try await store.sessions(kind: nil, query: "old words", limit: 10, offset: 0)
        XCTAssertTrue(search.isEmpty)
    }

    func testDeleteSessionCascadesSegmentsAndSearch() async throws {
        let session = makeSession()
        try await store.createSession(session)
        try await store.appendSegment(Segment(sessionID: session.id, index: 0, startMs: 0, endMs: 10,
                                              rawText: "delete me"))
        try await store.deleteSession(session.id)
        let deleted = try await store.session(session.id)
        let remainingSegments = try await store.segments(session: session.id)
        let search = try await store.sessions(kind: nil, query: "delete", limit: 10, offset: 0)
        XCTAssertNil(deleted)
        XCTAssertTrue(remainingSegments.isEmpty)
        XCTAssertTrue(search.isEmpty)
    }

    func testLexiconAndShortcutsRoundTrip() async throws {
        let term = LexiconEntry(kind: .term, triggers: ["super flow"], canonical: "Superflow")
        let correction = LexiconEntry(kind: .correction, triggers: ["there"], canonical: "their")
        try await store.saveLexicon(term)
        try await store.saveLexicon(correction)
        var lexicon = try await store.lexicon()
        XCTAssertEqual(lexicon.count, 2)
        XCTAssertEqual(lexicon.first { $0.id == term.id }?.triggers, ["super flow"])

        var updated = term
        updated.canonical = "SuperFlow"
        try await store.saveLexicon(updated)
        lexicon = try await store.lexicon()
        XCTAssertEqual(lexicon.first { $0.id == term.id }?.canonical, "SuperFlow")
        try await store.deleteLexicon(id: correction.id)
        let afterDelete = try await store.lexicon()
        XCTAssertEqual(afterDelete.count, 1)

        let shortcut = ShortcutEntry(trigger: "my signature", content: "Best,\nHarshit",
                                     match: .wholeUtterance)
        try await store.saveShortcut(shortcut)
        let shortcuts = try await store.shortcuts()
        XCTAssertEqual(shortcuts.first?.content, "Best,\nHarshit")
        try await store.deleteShortcut(id: shortcut.id)
        let afterShortcutDelete = try await store.shortcuts()
        XCTAssertTrue(afterShortcutDelete.isEmpty)
    }

    func testSettingsRoundTripAndCorruptJSONFallsBack() async throws {
        var settings = AppSettings.default
        settings.displayName = "Harshit"
        settings.retentionDays = 30
        settings.lineFormat.breakStyle = .newline
        await store.save(settings)
        let loaded = await store.load()
        XCTAssertEqual(loaded, settings)

        let connection = try SQLiteConnection(path: store.path)
        try connection.execute("UPDATE settings SET json = '{not json' WHERE key = 'app'")
        let fallback = await store.load()
        XCTAssertEqual(fallback, .default)
    }

    func testFactoryQuarantinesCorruptFile() async throws {
        let url = directory.appendingPathComponent("corrupt.sqlite")
        try Data("this is not sqlite".utf8).write(to: url)
        let opened = try SQLiteStoreFactory.open(url: url)
        let count = try await opened.sessionCount(kind: nil)
        XCTAssertEqual(count, 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.contains("Superflow-corrupt") })
    }

    func testMigrationsAreIdempotent() async throws {
        let path = directory.appendingPathComponent("migrate.sqlite").path
        _ = try SQLiteStore(path: path)
        let reopened = try SQLiteStore(path: path)
        let count = try await reopened.sessionCount(kind: nil)
        XCTAssertEqual(count, 0)
    }
}
