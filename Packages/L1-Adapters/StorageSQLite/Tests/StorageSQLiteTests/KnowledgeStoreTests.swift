import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowStorageSQLite

/// Real, ephemeral SQLite databases only. These exercise the DB logic itself —
/// CRUD, full-text search, ordering, migration, concurrency and restart — with
/// no mocks or in-memory substitutes.
final class KnowledgeStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SQLiteStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-knowledge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try SQLiteStore(path: directory.appendingPathComponent("knowledge.sqlite").path)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func reopen() async throws -> SQLiteStore {
        store = nil
        let opened = try SQLiteStore(path: directory.appendingPathComponent("knowledge.sqlite").path)
        store = opened
        return opened
    }

    // MARK: - CRUD

    func testLexiconCRUDEmptyDuplicateUpdateDeleteAndRestart() async throws {
        let initialLexicon = try await store.lexicon()
        let initialShortcuts = try await store.shortcuts()
        XCTAssertTrue(initialLexicon.isEmpty, "a fresh database has no terms")
        XCTAssertTrue(initialShortcuts.isEmpty, "a fresh database has no shortcuts")

        let term = LexiconEntry(id: "term-1", kind: .term, triggers: ["super flow"],
                                canonical: "Superflow")
        let correction = LexiconEntry(id: "cor-1", kind: .correction, triggers: ["there"],
                                      canonical: "their")
        try await store.saveLexicon(term)
        try await store.saveLexicon(correction)

        // Idempotent by id: saving the same id twice updates, never appends.
        var renamed = term
        renamed.canonical = "SuperFlow"
        try await store.saveLexicon(renamed)
        var all = try await store.lexicon()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.id == term.id }?.canonical, "SuperFlow")

        try await store.deleteLexicon(id: correction.id)
        all = try await store.lexicon()
        XCTAssertEqual(all.map(\.id), ["term-1"])

        // Restart persistence.
        let reopened = try await reopen()
        let loaded = try await reopened.lexicon()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.canonical, "SuperFlow")
        XCTAssertEqual(loaded.first?.triggers, ["super flow"])
    }

    func testShortcutCRUDDuplicateUpdateDeleteAndRestart() async throws {
        let shortcut = ShortcutEntry(id: "short-1", trigger: "my signature",
                                     content: "Best,\nHarshit", match: .wholeUtterance)
        try await store.saveShortcut(shortcut)
        var updated = shortcut
        updated.content = "Cheers"
        updated.match = .inline
        try await store.saveShortcut(updated)
        try await store.saveShortcut(updated) // idempotent

        let all = try await store.shortcuts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "Cheers")
        XCTAssertEqual(all.first?.match, .inline)

        let reopened = try await reopen()
        let afterRestart = try await reopened.shortcuts()
        XCTAssertEqual(afterRestart.count, 1)
        try await reopened.deleteShortcut(id: shortcut.id)
        let afterDelete = try await reopened.shortcuts()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testDeterministicOrderingSurvivesInsertionOrderAndRestart() async throws {
        // Same canonical, different enabled flags and ids: ordering must not
        // depend on insertion order or SQLite rowid.
        let entries = [
            LexiconEntry(id: "z", kind: .term, triggers: ["c"], canonical: "Beta", enabled: false),
            LexiconEntry(id: "a", kind: .term, triggers: ["a"], canonical: "beta"),
            LexiconEntry(id: "m", kind: .term, triggers: ["b"], canonical: "Beta"),
            LexiconEntry(id: "q", kind: .term, triggers: ["d"], canonical: "Alpha"),
        ]
        for entry in entries.reversed() { try await store.saveLexicon(entry) }
        let firstOrder = try await store.lexicon().map(\.id)
        XCTAssertEqual(firstOrder, ["q", "a", "m", "z"])

        let reopened = try await reopen()
        let secondOrder = try await reopened.lexicon().map(\.id)
        XCTAssertEqual(secondOrder, firstOrder)

        let shortcuts = [
            ShortcutEntry(id: "s2", trigger: "beta", content: "2", enabled: false),
            ShortcutEntry(id: "s1", trigger: "Alpha", content: "1"),
            ShortcutEntry(id: "s3", trigger: "alpha", content: "3"),
        ]
        for shortcut in shortcuts { try await store.saveShortcut(shortcut) }
        let shortcutOrder = try await store.shortcuts().map(\.id)
        XCTAssertEqual(shortcutOrder, ["s1", "s3", "s2"])
    }

    // MARK: - Full-text search

    func testLexiconFullTextSearchAcrossCanonicalAndTriggers() async throws {
        try await store.saveLexicon(LexiconEntry(id: "1", kind: .term,
                                                 triggers: ["next js"], canonical: "Next.js"))
        try await store.saveLexicon(LexiconEntry(id: "2", kind: .correction,
                                                 triggers: ["item potency"], canonical: "idempotency"))
        try await store.saveLexicon(LexiconEntry(id: "3", kind: .term,
                                                 triggers: ["tan stack"], canonical: "TanStack Query"))

        let byNext = try await store.searchLexicon(query: "next")
        let byJS = try await store.searchLexicon(query: "js")
        let byCase = try await store.searchLexicon(query: "ITEM potency")
        let byCanonical = try await store.searchLexicon(query: "idempotency")
        let multi = try await store.searchLexicon(query: "next js")
        let conflicting = try await store.searchLexicon(query: "next tan")
        let missing = try await store.searchLexicon(query: "missing")
        let blank = try await store.searchLexicon(query: "   ")
        let limited = try await store.searchLexicon(query: "tan", limit: 1)
        let zero = try await store.searchLexicon(query: "tan", limit: 0)

        XCTAssertEqual(byNext.map(\.id), ["1"])
        XCTAssertEqual(byJS.map(\.id), ["1"])
        XCTAssertEqual(byCase.map(\.id), ["2"])
        XCTAssertEqual(byCanonical.map(\.id), ["2"])
        XCTAssertEqual(multi.map(\.id), ["1"])
        XCTAssertTrue(conflicting.isEmpty, "multiple terms are ANDed")
        XCTAssertTrue(missing.isEmpty)
        XCTAssertTrue(blank.isEmpty)
        XCTAssertEqual(limited.count, 1)
        XCTAssertTrue(zero.isEmpty)
    }

    func testShortcutFullTextSearchAcrossTriggerAndContent() async throws {
        try await store.saveShortcut(ShortcutEntry(id: "1", trigger: "my calendar link",
                                                   content: "https://cal.com/me"))
        try await store.saveShortcut(ShortcutEntry(id: "2", trigger: "standup notes",
                                                   content: "## Standup\n- Yesterday"))
        let byTrigger = try await store.searchShortcuts(query: "calendar")
        let byContent = try await store.searchShortcuts(query: "yesterday")
        let byStandup = try await store.searchShortcuts(query: "standup")
        let missing = try await store.searchShortcuts(query: "nothing")
        XCTAssertEqual(byTrigger.map(\.id), ["1"])
        XCTAssertEqual(byContent.map(\.id), ["2"])
        XCTAssertEqual(byStandup.map(\.id), ["2"])
        XCTAssertTrue(missing.isEmpty)
    }

    func testSearchIndexStaysInSyncOnUpdateAndDelete() async throws {
        let entry = LexiconEntry(id: "1", kind: .term, triggers: ["old phrase"], canonical: "Old Name")
        try await store.saveLexicon(entry)
        let before = try await store.searchLexicon(query: "old")
        XCTAssertEqual(before.map(\.id), ["1"])

        var updated = entry
        updated.triggers = ["new phrase"]
        updated.canonical = "New Name"
        try await store.saveLexicon(updated)
        let stale = try await store.searchLexicon(query: "old")
        let fresh = try await store.searchLexicon(query: "new")
        XCTAssertTrue(stale.isEmpty)
        XCTAssertEqual(fresh.map(\.id), ["1"])

        try await store.deleteLexicon(id: entry.id)
        let afterDelete = try await store.searchLexicon(query: "new")
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testHostileFTSQueriesDoNotThrowOrLeakRows() async throws {
        try await store.saveLexicon(LexiconEntry(id: "1", kind: .term,
                                                 triggers: ["safe"], canonical: "Safe Term"))
        for query in ["\"unbalanced", "*", "(", "NEAR(", "a OR", "\\", "]:", "   "] {
            let results = try await store.searchLexicon(query: query)
            XCTAssertTrue(results.isEmpty, "hostile query \(query) must not match")
        }
        let safe = try await store.searchLexicon(query: "safe")
        XCTAssertEqual(safe.map(\.id), ["1"])
    }

    // MARK: - Long, unicode, and adversarial values

    func testLongUnicodeAndEscapedValuesRoundTripAndSearch() async throws {
        let canonical = String(repeating: "価格", count: 100) // 200 unicode scalars
        let entry = LexiconEntry(id: "unicode-1", kind: .correction,
                                 triggers: ["café ☕ 東京", "quote \" and, comma"],
                                 canonical: canonical)
        try await store.saveLexicon(entry)
        let loaded = try await store.lexicon()
        XCTAssertEqual(loaded.first?.canonical, canonical)
        XCTAssertEqual(loaded.first?.triggers, ["café ☕ 東京", "quote \" and, comma"])

        let reopened = try await reopen()
        let persisted = try await reopened.lexicon()
        XCTAssertEqual(persisted.first?.canonical, canonical)
        let byPlace = try await reopened.searchLexicon(query: "東京")
        let byAccent = try await reopened.searchLexicon(query: "café")
        XCTAssertEqual(byPlace.map(\.id), ["unicode-1"])
        XCTAssertEqual(byAccent.map(\.id), ["unicode-1"])
    }

    // MARK: - Concurrency

    func testConcurrentWritesAreSerializedAndNothingIsLost() async throws {
        let count = 24
        // Capture the actor, not `self` (XCTestCase is not Sendable).
        let database = store!
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask {
                    try await database.saveLexicon(
                        LexiconEntry(id: "lex-\(index)", kind: .term,
                                     triggers: ["term\(index)"], canonical: "Term \(index)"))
                    try await database.saveShortcut(
                        ShortcutEntry(id: "cut-\(index)", trigger: "phrase \(index)",
                                      content: "body \(index)"))
                    try await database.saveLearningCandidate(
                        LearningCandidate(id: "cand-\(index)", heard: "heard \(index)",
                                          canonical: "canon \(index)", confidence: 0.5))
                }
            }
            try await group.waitForAll()
        }
        let lexicon = try await store.lexicon()
        let shortcuts = try await store.shortcuts()
        let candidates = try await store.learningCandidates()
        let searched = try await store.searchLexicon(query: "term")
        XCTAssertEqual(lexicon.count, count)
        XCTAssertEqual(Set(lexicon.map(\.id)).count, count)
        XCTAssertEqual(shortcuts.count, count)
        XCTAssertEqual(candidates.count, count)
        XCTAssertEqual(searched.count, count)

        let reopened = try await reopen()
        let persistedLexicon = try await reopened.lexicon()
        let persistedShortcuts = try await reopened.shortcuts()
        let persistedCandidates = try await reopened.learningCandidates()
        XCTAssertEqual(persistedLexicon.count, count)
        XCTAssertEqual(persistedShortcuts.count, count)
        XCTAssertEqual(persistedCandidates.count, count)
    }

    // MARK: - Learning candidates

    func testLearningCandidatesPersistAllStatesAndReloadAfterRestart() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let suggested = LearningCandidate(id: "s", heard: "item potency", canonical: "idempotency",
                                          confidence: 0.7, observations: 1, state: .suggested,
                                          createdAt: now, updatedAt: now)
        let confirmed = LearningCandidate(id: "c", heard: "nextjs", canonical: "Next.js",
                                          appScope: "com.microsoft.VSCode", confidence: 0.9,
                                          observations: 3, state: .confirmed,
                                          createdAt: now, updatedAt: now)
        let rejected = LearningCandidate(id: "r", heard: "pearl", canonical: "Perl",
                                         confidence: 0.4, observations: 1, state: .rejected,
                                         createdAt: now, updatedAt: now)
        for candidate in [suggested, confirmed, rejected] {
            try await store.saveLearningCandidate(candidate)
        }
        // Idempotent upsert.
        try await store.saveLearningCandidate(confirmed)

        let reopened = try await reopen()
        let loaded = try await reopened.learningCandidates()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertTrue(loaded.contains(suggested))
        XCTAssertTrue(loaded.contains(confirmed))
        XCTAssertTrue(loaded.contains(rejected))

        try await reopened.deleteLearningCandidate(id: "r")
        let afterDelete = try await reopened.learningCandidates()
        XCTAssertEqual(afterDelete.count, 2)
    }

    // MARK: - Migration and idempotency

    func testV1KnowledgeRowsMigrateForwardWithBackfilledSearch() async throws {
        let url = directory.appendingPathComponent("legacy.sqlite")
        do {
            let connection = try SQLiteConnection(path: url.path)
            try connection.execute(Schema.v1)
            try connection.setUserVersion(1)
            try connection.execute("""
            INSERT INTO lexicon_entries (id, kind, triggers, canonical, enabled, source)
            VALUES ('legacy-term', 'term', '["next js"]', 'Next.js', 1, 'user');
            INSERT INTO shortcuts (id, trigger, content, match, enabled)
            VALUES ('legacy-cut', 'calendar link', 'https://cal.com/me', 'wholeUtterance', 1);
            """)
        }

        let migrated = try SQLiteStore(path: url.path)
        let connection = try SQLiteConnection(path: url.path)
        XCTAssertEqual(try connection.userVersion, Schema.currentVersion)
        let lexicon = try await migrated.lexicon()
        let foundTerm = try await migrated.searchLexicon(query: "next")
        let foundCut = try await migrated.searchShortcuts(query: "calendar")
        XCTAssertEqual(lexicon.map(\.id), ["legacy-term"])
        XCTAssertEqual(foundTerm.map(\.id), ["legacy-term"])
        XCTAssertEqual(foundCut.map(\.id), ["legacy-cut"])

        // Reopening twice must not duplicate or remove anything.
        _ = try SQLiteStore(path: url.path)
        let again = try SQLiteStore(path: url.path)
        XCTAssertEqual(try connection.userVersion, Schema.currentVersion)
        let againTerm = try await again.searchLexicon(query: "next")
        let againCut = try await again.searchShortcuts(query: "calendar")
        XCTAssertEqual(againTerm.count, 1)
        XCTAssertEqual(againCut.count, 1)
    }

    func testFTS5TablesExistAndUseExternalContent() throws {
        let connection = try SQLiteConnection(path: store.path)
        for table in ["lexicon_search", "shortcut_search"] {
            let sql = try connection.scalarText(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", [.text(table)])
            XCTAssertNotNil(sql, "\(table) must exist")
            XCTAssertTrue(sql?.lowercased().contains("fts5") == true)
            XCTAssertTrue(sql?.lowercased().contains("content=") == true)
        }
        let triggers = try connection.scalarInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name LIKE '%_search_%'")
        XCTAssertGreaterThanOrEqual(triggers, 6)
    }
}
