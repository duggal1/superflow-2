import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureHistory

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testNewDictationAppearsWithoutReload() async throws {
        let repository = InMemoryRepository()
        let model = HistoryViewModel(repository: repository, inserter: RecordingInserter())
        await model.load()
        let session = SessionRecord(id: SessionID("live"), kind: .dictation,
                                    status: .complete, modelProfile: "test")
        try await repository.createSession(session)
        // The store posts this after every write; the double stays passive.
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
        var waited = 0
        while model.sessions.isEmpty && waited < 100 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        XCTAssertEqual(model.sessions.map(\.id), [session.id])
    }

    private var repository: InMemoryRepository!
    private var inserter: RecordingInserter!
    private var model: HistoryViewModel!

    override func setUp() async throws {
        repository = InMemoryRepository()
        inserter = RecordingInserter()
        model = HistoryViewModel(repository: repository, inserter: inserter)
    }

    private func makeSession(id: String, kind: SessionKind = .dictation,
                             startedAt: Date = Date(timeIntervalSince1970: 1_000),
                             texts: [String] = ["hello world"], speakers: [String] = []) async throws {
        let sessionID = SessionID(id)
        let words = texts.reduce(0) { $0 + wordCount($1) }
        try await repository.createSession(
            SessionRecord(id: sessionID, kind: kind, startedAt: startedAt,
                          endedAt: startedAt.addingTimeInterval(12), status: .complete,
                          modelProfile: "base", durationMs: 12_000, wordCount: words,
                          cleanupState: .cleaned))
        for (index, text) in texts.enumerated() {
            try await repository.appendSegment(
                Segment(sessionID: sessionID, index: index, startMs: index * 1_000,
                        endMs: (index + 1) * 1_000,
                        speakerID: speakers.isEmpty ? nil : "speaker-\(index % speakers.count)",
                        rawText: "raw \(text)", cleanedText: text, cleanupState: .cleaned))
        }
        for (index, name) in speakers.enumerated() {
            try await repository.upsertSpeaker(
                SpeakerRecord(sessionID: sessionID, id: "speaker-\(index)", label: name,
                              isSelf: index == 0))
        }
    }

    func testLoadSelectsNewestAndReadsSegments() async throws {
        try await makeSession(id: "old", startedAt: Date(timeIntervalSince1970: 100))
        try await makeSession(id: "new", startedAt: Date(timeIntervalSince1970: 200),
                              texts: ["newer transcript"])
        await model.load()

        XCTAssertNil(model.error)
        XCTAssertEqual(model.sessions.map(\.id.value), ["new", "old"])
        XCTAssertEqual(model.selectedID?.value, "new")
        XCTAssertEqual(model.segments.count, 1)
        XCTAssertEqual(model.fullText, "newer transcript")
    }

    func testFilterReloadsByKind() async throws {
        try await makeSession(id: "dictation", startedAt: Date(timeIntervalSince1970: 100))
        try await makeSession(id: "meeting", kind: .meeting,
                              startedAt: Date(timeIntervalSince1970: 200))
        await model.load()
        XCTAssertEqual(model.sessions.count, 2)

        model.filter = .meetings
        await model.load()
        XCTAssertEqual(model.sessions.map(\.id.value), ["meeting"])
    }

    func testSearchMatchesTranscriptText() async throws {
        try await makeSession(id: "budget", startedAt: Date(timeIntervalSince1970: 100),
                              texts: ["we reviewed the quarterly budget"])
        try await makeSession(id: "other", startedAt: Date(timeIntervalSince1970: 200),
                              texts: ["unrelated notes"])
        model.query = "quarterly"
        await model.load()
        XCTAssertEqual(model.sessions.map(\.id.value), ["budget"])
    }

    func testPaginationAppendsOlderSessions() async throws {
        for index in 0..<3 {
            try await makeSession(id: "s\(index)",
                                  startedAt: Date(timeIntervalSince1970: Double(100 + index)))
        }
        model = HistoryViewModel(repository: repository, inserter: inserter, pageSize: 2)
        await model.load()
        XCTAssertEqual(model.sessions.count, 2)
        XCTAssertTrue(model.hasMore)

        await model.loadMore()
        XCTAssertEqual(model.sessions.count, 3)
        XCTAssertFalse(model.hasMore)
    }

    func testCopyUsesCleanedOrRawTextWithSpeakerNames() async throws {
        try await makeSession(id: "meeting", kind: .meeting, texts: ["my update", "their reply"],
                              speakers: ["Harshit", "Priya"])
        await model.load()

        await model.copySelected()
        let copied = await inserter.inserted
        XCTAssertEqual(copied, ["Harshit: my update\nPriya: their reply"])
        XCTAssertEqual(model.toast.current?.text, "Copied to the clipboard.")

        model.showRaw = true
        XCTAssertEqual(model.fullText, "Harshit: raw my update\nPriya: raw their reply")
        XCTAssertEqual(model.speakerName(for: model.segments[0]), "Harshit")
    }

    func testDeleteAdjustsDailyStatsAndUndoRestores() async throws {
        try await makeSession(id: "s1", texts: ["one two three"])
        try await repository.addDailyStat(DailyStat(day: modelDay(for: 1_000), words: 100,
                                                    audioMs: 60_000, sessions: 4))
        await model.load()
        let day = modelDay(for: 1_000)

        await model.deleteSelected()
        XCTAssertTrue(model.sessions.isEmpty)
        var stats = try await repository.dailyStats(fromDay: day, toDay: day)
        XCTAssertEqual(stats.first?.words, 97)
        XCTAssertEqual(stats.first?.sessions, 3)
        XCTAssertEqual(stats.first?.audioMs, 48_000)
        XCTAssertEqual(model.toast.current?.actionTitle, "Undo")

        await model.undoDelete()
        stats = try await repository.dailyStats(fromDay: day, toDay: day)
        XCTAssertEqual(stats.first?.words, 100)
        XCTAssertEqual(stats.first?.sessions, 4)
        XCTAssertEqual(model.selectedID?.value, "s1")
        XCTAssertEqual(model.segments.count, 1)
    }

    func testSelectNextAndPreviousFollowListOrder() async throws {
        for index in 0..<3 {
            try await makeSession(id: "s\(index)",
                                  startedAt: Date(timeIntervalSince1970: Double(100 + index)))
        }
        await model.load()
        XCTAssertEqual(model.selectedID?.value, "s2")

        await model.selectNext()
        XCTAssertEqual(model.selectedID?.value, "s1")
        await model.selectNext()
        XCTAssertEqual(model.selectedID?.value, "s0")
        await model.selectNext()
        XCTAssertEqual(model.selectedID?.value, "s0")
        await model.selectPrevious()
        XCTAssertEqual(model.selectedID?.value, "s1")
    }

    private func modelDay(for timestamp: TimeInterval) -> String {
        LocalDay.string(for: Date(timeIntervalSince1970: timestamp))
    }
}
