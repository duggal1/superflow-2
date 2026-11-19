import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowStorageSQLite

/// Focused checks for the backend ideas ported from the read-only Hex reference.
/// Every test uses a real, ephemeral SQLite database and real files.
final class PortedBackendTests: XCTestCase {
    private func tempDirectory(_ tag: String = "port") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-port-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func finishedSession(_ id: SessionID,
                                 startedAt: Date = Date(timeIntervalSince1970: 1)) -> SessionRecord {
        SessionRecord(id: id, kind: .dictation, startedAt: startedAt, status: .complete,
                      modelProfile: "parakeet-eou-120m")
    }

    // MARK: 1. bounded paged reads

    func testPagedSegmentReadsAreKeysetBoundedAndOrdered() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("long")
        try await store.createSession(finishedSession(id))
        for index in 0..<5 {
            try await store.appendSegment(Segment(sessionID: id, index: index,
                                                   startMs: index * 1_000, endMs: (index + 1) * 1_000,
                                                   rawText: "segment \(index)"))
        }

        let first = try await store.segmentPage(session: id, limit: 2)
        XCTAssertEqual(first.segments.map(\.index), [0, 1])
        XCTAssertEqual(first.nextIndex, 1)
        XCTAssertFalse(first.isLast)

        let second = try await store.segmentPage(session: id, afterIndex: first.nextIndex ?? -1, limit: 2)
        XCTAssertEqual(second.segments.map(\.index), [2, 3])
        XCTAssertEqual(second.nextIndex, 3)

        let last = try await store.segmentPage(session: id, afterIndex: second.nextIndex ?? -1, limit: 2)
        XCTAssertEqual(last.segments.map(\.index), [4])
        XCTAssertNil(last.nextIndex)
        XCTAssertTrue(last.isLast)

        let pastEnd = try await store.segmentPage(session: id, afterIndex: 10, limit: 2)
        XCTAssertTrue(pastEnd.segments.isEmpty)
        XCTAssertNil(pastEnd.nextIndex)
    }

    func testSegmentPageIsCappedEvenWhenAskedForMore() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("capped")
        try await store.createSession(finishedSession(id))
        let count = SQLiteStore.maximumSegmentPageSize + 2
        let segments = (0..<count).map { index in
            Segment(sessionID: id, index: index, startMs: 0, endMs: 1, rawText: "s\(index)")
        }
        try await store.upsertSegments(segments)
        let page = try await store.segmentPage(session: id, limit: 99_999)
        XCTAssertEqual(page.segments.count, SQLiteStore.maximumSegmentPageSize,
                       "a page is hard-capped regardless of the requested limit")
        XCTAssertEqual(page.nextIndex, SQLiteStore.maximumSegmentPageSize - 1)
    }

    func testSegmentPageSequenceStreamsEverySegment() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("stream")
        try await store.createSession(finishedSession(id))
        for index in 0..<7 {
            try await store.appendSegment(Segment(sessionID: id, index: index,
                                                   startMs: 0, endMs: 1, rawText: "s\(index)"))
        }

        var seen: [Int] = []
        for try await page in await store.segmentPages(session: id, pageSize: 3) {
            seen.append(contentsOf: page.segments.map(\.index))
        }
        XCTAssertEqual(seen, Array(0..<7))
    }

    // MARK: 2. idempotent upserts with stable ids

    func testUpsertSegmentsIsIdempotentByStableID() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("upsert")
        try await store.createSession(finishedSession(id))

        let first = Segment(sessionID: id, index: 0, startMs: 0, endMs: 10, rawText: "alpha")
        let second = Segment(sessionID: id, index: 1, startMs: 10, endMs: 20, rawText: "beta")
        try await store.upsertSegments([first, second])
        try await store.upsertSegments([
            Segment(sessionID: id, index: 0, startMs: 0, endMs: 10, rawText: "alpha revised"),
            second,
        ])

        let stored = try await store.segments(session: id)
        XCTAssertEqual(stored.count, 2, "a replay must not duplicate stable ids")
        XCTAssertEqual(stored.first { $0.index == 0 }?.rawText, "alpha revised")
        let found = try await store.sessions(kind: nil, query: "revised", limit: 10, offset: 0)
        XCTAssertEqual(found.map(\.id), [id], "FTS follows the upsert")
    }

    func testUpsertSpeakersIsIdempotentByStableID() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("speakers")
        try await store.createSession(finishedSession(id))
        let speaker = SpeakerRecord(sessionID: id, id: "remote-1", label: "Speaker 1", isSelf: false)
        try await store.upsertSpeakers([speaker])
        try await store.upsertSpeakers([
            SpeakerRecord(sessionID: id, id: "remote-1", label: "Priya", isSelf: false),
        ])
        let stored = try await store.speakers(session: id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.label, "Priya")
    }

    // MARK: 3. versioned export

    func testExportDocumentJSONAndMarkdown() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        var session = finishedSession(SessionID("export"))
        session.title = "Design sync"
        session.durationMs = 60_000
        session.wordCount = 42
        session.endedAt = Date(timeIntervalSince1970: 61)
        try await store.createSession(session)
        try await store.upsertSpeakers([
            SpeakerRecord(sessionID: session.id, id: "self", label: "You", isSelf: true),
            SpeakerRecord(sessionID: session.id, id: "r1", label: "Priya", isSelf: false),
        ])
        try await store.upsertSegments([
            Segment(sessionID: session.id, index: 0, startMs: 500, endMs: 3_000,
                    speakerID: "self", source: .mic, rawText: "um hello", cleanedText: "Hello"),
            Segment(sessionID: session.id, index: 1, startMs: 3_000, endMs: 6_000,
                    speakerID: "r1", source: .system, rawText: "hi there"),
        ])

        let document = try await store.exportDocument(session: session.id)
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.metadata.sessionID, "export")
        XCTAssertEqual(document.metadata.title, "Design sync")
        XCTAssertEqual(document.metadata.durationMs, 60_000)
        XCTAssertEqual(Set(document.speakers.map(\.label)), ["You", "Priya"])
        XCTAssertEqual(document.segments.count, 2)
        XCTAssertEqual(document.segments[0].start, 500)
        XCTAssertEqual(document.segments[0].end, 3_000)
        XCTAssertEqual(document.segments[0].source, "mic")
        XCTAssertEqual(document.segments[0].speaker, "self")
        XCTAssertEqual(document.segments[0].raw, "um hello")
        XCTAssertEqual(document.segments[0].final, "Hello")
        XCTAssertEqual(document.segments[1].final, "hi there")

        let json = try await store.exportJSON(session: session.id)
        let decoded = try JSONDecoder().decode(TranscriptExportDocument.self, from: json)
        XCTAssertEqual(decoded, document)
        XCTAssertTrue(String(data: json, encoding: .utf8)?.contains("schemaVersion") == true)

        let markdown = try await store.exportMarkdown(session: session.id)
        XCTAssertTrue(markdown.hasPrefix("# Design sync"))
        XCTAssertTrue(markdown.contains("## Speakers"))
        XCTAssertTrue(markdown.contains("- Priya"))
        XCTAssertTrue(markdown.contains("Hello"))
        XCTAssertTrue(markdown.contains("hi there"))
        XCTAssertTrue(markdown.contains("**["))
    }

    func testExportMissingSessionThrows() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        do {
            _ = try await store.exportDocument(session: SessionID("absent"))
            XCTFail("export of a missing session must fail")
        } catch TranscriptExportError.sessionNotFound(let id) {
            XCTAssertEqual(id, "absent")
        }
    }

    // MARK: 4. integrity check + quarantine

    func testIntegrityCheckOfHealthyDatabase() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        try await store.createSession(finishedSession(SessionID("healthy")))
        let result = DatabaseIntegrity.check(databaseAt: URL(fileURLWithPath: store.path))
        XCTAssertEqual(result, .healthy)
    }

    func testQuarantinePreservesDatabaseAndSidecars() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doomed.sqlite")
        let wal = URL(fileURLWithPath: url.path + "-wal")
        try Data("database bytes".utf8).write(to: url)
        try Data("wal bytes".utf8).write(to: wal)

        let destination = try DatabaseIntegrity.quarantine(databaseAt: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wal.path))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("doomed.sqlite")),
                       Data("database bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("doomed.sqlite-wal")),
                       Data("wal bytes".utf8))
        XCTAssertTrue(destination.lastPathComponent.contains("doomed"))
    }

    func testOpenWithIntegrityCheckQuarantinesCorruptDatabase() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("corrupt.sqlite")
        do {
            let store = try SQLiteStore(path: url.path)
            try await store.createSession(finishedSession(SessionID("corrupt")))
        }
        // Drop WAL sidecars so a valid frame cannot replay over the damaged page.
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        var data = try Data(contentsOf: url)
        // Damage the schema page and a page in the middle of the file: a valid
        // header stays, but integrity_check must find broken pages.
        for offset in [4_096, data.count / 2] {
            let start = min(offset, max(0, data.count - 512))
            let end = min(start + 512, data.count)
            if end > start {
                data.replaceSubrange(start..<end, with: Data(repeating: 0xFF, count: end - start))
            }
        }
        try data.write(to: url)

        XCTAssertThrowsError(try SQLiteStoreFactory.openWithIntegrityCheck(url: url)) { error in
            guard let integrityError = error as? DatabaseIntegrity.IntegrityError,
                  case .corruptedDatabaseQuarantined(let path) = integrityError else {
                return XCTFail("expected a quarantine error, got \(error)")
            }
            XCTAssertTrue(path.contains(".superflow-quarantine"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "the corrupt file was moved, not deleted in place")
        let root = directory.appendingPathComponent(".superflow-quarantine", isDirectory: true)
        let items = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(items[0])
                                .appendingPathComponent("corrupt.sqlite")), data,
                       "the quarantined bytes are preserved unchanged")
    }

    // MARK: 5. retention sweep

    func testRetentionDefersRemovalAndUndoCancels() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("clip")
        try await store.createSession(finishedSession(id))
        try await store.setAudio(session: id, duration: 1, peaks: Data([1, 2, 3]))
        let clip = audio.appendingPathComponent("\(id.value).m4a")
        try Data("audio".utf8).write(to: clip)

        let configuration = RetentionSweeper.Configuration(retentionDays: 0,
                                                            audioDirectory: audio,
                                                            checkIntegrityOnPass: false)
        let sweeper = RetentionSweeper(store: store, configuration: configuration)
        let report = try await sweeper.runPass()
        XCTAssertEqual(report.removalsScheduled, 1)
        let pendingCount = await sweeper.pendingRemovalCount
        XCTAssertEqual(pendingCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path),
                      "the grace period keeps the clip on disk")
        let stillThere = try await store.session(id)
        XCTAssertNotNil(stillThere)

        let cancelled = await sweeper.cancelRemoval(session: id)
        XCTAssertTrue(cancelled)
        await sweeper.flushPendingRemovals()
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path),
                      "Undo cancels the scheduled removal")
        let afterUndo = try await store.session(id)
        XCTAssertNotNil(afterUndo)
    }

    func testRetentionFlushTrashesClipAndDropsRow() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("flush")
        try await store.createSession(finishedSession(id))
        try await store.setAudio(session: id, duration: 1, peaks: Data([1]))
        let clip = audio.appendingPathComponent("\(id.value).m4a")
        try Data("audio".utf8).write(to: clip)

        let configuration = RetentionSweeper.Configuration(retentionDays: 0,
                                                            audioDirectory: audio,
                                                            checkIntegrityOnPass: false)
        let sweeper = RetentionSweeper(store: store, configuration: configuration)
        _ = try await sweeper.runPass()
        await sweeper.flushPendingRemovals()
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.path),
                       "the clip is gone from the clips folder (moved to Trash)")
        let session = try await store.session(id)
        XCTAssertNil(session)
        let withAudio = try await store.sessionsWithAudio()
        XCTAssertTrue(withAudio.isEmpty)
    }

    func testRetentionNullsMetadataForMissingClip() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("missing-clip")
        try await store.createSession(finishedSession(id))
        try await store.setAudio(session: id, duration: 9, peaks: Data([9, 9]))

        let configuration = RetentionSweeper.Configuration(retentionDays: 7,
                                                            audioDirectory: audio,
                                                            checkIntegrityOnPass: false)
        let sweeper = RetentionSweeper(store: store, configuration: configuration)
        let repaired = try await sweeper.repairMissingClipMetadata()
        XCTAssertEqual(repaired, 1)
        let session = try await store.session(id)
        XCTAssertNil(session?.audioDuration)
        XCTAssertNil(session?.audioPeaks)
        XCTAssertNotNil(session, "metadata repair does not delete the row")
    }

    func testRetentionForeverDoesNoWork() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let store = try SQLiteStore(path: directory.appendingPathComponent("store.sqlite").path)
        let id = SessionID("forever")
        try await store.createSession(finishedSession(id))
        try await store.setAudio(session: id, duration: 1, peaks: Data([1]))
        let clip = audio.appendingPathComponent("\(id.value).m4a")
        try Data("audio".utf8).write(to: clip)

        let configuration = RetentionSweeper.Configuration(retentionDays: nil,
                                                            audioDirectory: audio,
                                                            checkIntegrityOnPass: false)
        let sweeper = RetentionSweeper(store: store, configuration: configuration)
        let report = try await sweeper.runPass()
        XCTAssertEqual(report.removalsScheduled, 0)
        XCTAssertEqual(report.missingClipMetadataNulled, 0)
        XCTAssertEqual(report.orphanClipsScheduled, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))
        let untouched = try await store.session(id)
        XCTAssertNotNil(untouched)
    }

    func testDailyDateIsTomorrow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let next = RetentionSweeper.nextDailyDate(from: now)
        XCTAssertGreaterThan(next, now)
        XCTAssertLessThanOrEqual(next.timeIntervalSince(now), 86_400)
    }
}
