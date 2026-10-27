import Foundation
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowTestKit
import SuperflowTextPipeline
import XCTest
@testable import SuperflowFeatureMeetings

@MainActor
final class MeetingsViewModelTests: XCTestCase {
    private var repository: InMemoryRepository!
    private var inserter: RecordingInserter!

    override func setUp() async throws {
        repository = InMemoryRepository()
        inserter = RecordingInserter()
    }

    private func makePastMeeting(id: String = "past-1", title: String = "Weekly sync",
                                 startedAt: Date = Date(timeIntervalSince1970: 1_000)) async throws -> SessionID {
        let sessionID = SessionID(id)
        try await repository.createSession(
            SessionRecord(id: sessionID, kind: .meeting, startedAt: startedAt,
                          endedAt: startedAt.addingTimeInterval(600), status: .complete,
                          modelProfile: "base", durationMs: 600_000, wordCount: 4,
                          cleanupState: .cleaned, title: title))
        try await repository.appendSegment(
            Segment(sessionID: sessionID, index: 0, startMs: 0, endMs: 5_000,
                    speakerID: "self", source: .mic, rawText: "my update",
                    cleanedText: "My update.", cleanupState: .cleaned))
        try await repository.appendSegment(
            Segment(sessionID: sessionID, index: 1, startMs: 6_000, endMs: 9_000,
                    speakerID: "remote-1", source: .system, rawText: "their reply",
                    cleanedText: "Their reply.", cleanupState: .cleaned))
        try await repository.appendSegment(
            Segment(sessionID: sessionID, index: 2, startMs: 10_000, endMs: 10_000,
                    speakerID: "system", source: .system, rawText: "[System audio lost]",
                    cleanupState: .skipped))
        try await repository.upsertSpeaker(
            SpeakerRecord(sessionID: sessionID, id: "self", label: "Harshit", isSelf: true))
        try await repository.upsertSpeaker(
            SpeakerRecord(sessionID: sessionID, id: "remote-1", label: "Speaker 1", isSelf: false))
        return sessionID
    }

    private func makeEngine() -> MeetingEngine {
        let mic = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .mic)
        let system = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .system)
        let recognizer = FakeSpeechRecognizer(
            script: ["hello"],
            scriptsBySource: [.mic: ["my update"], .system: ["their reply"]],
            samplesPerSegment: 80_000)
        return MeetingEngine(mic: mic, system: system, recognizer: recognizer,
                             pipeline: TextPipeline(stages: []),
                             repository: repository, journals: FakeJournalStore())
    }

    func testLoadPastBuildsDocumentAndFlagsGaps() async throws {
        _ = try await makePastMeeting()
        let model = MeetingsViewModel(engine: nil, repository: repository, inserter: inserter)
        await model.loadPast()

        XCTAssertEqual(model.pastSessions.count, 1)
        XCTAssertEqual(model.selectedID?.value, "past-1")
        let document = try XCTUnwrap(model.selectedDocument)
        XCTAssertEqual(document.title, "Weekly sync")
        XCTAssertEqual(document.turns.count, 3)
        XCTAssertEqual(document.turns.filter(\.isGap).count, 1)
        XCTAssertEqual(document.speakers.first { $0.isSelf }?.name, "Harshit")
        XCTAssertEqual(model.selectedSpeakers.count, 2)
    }

    func testCopyAndExportsUseSelectedDocument() async throws {
        _ = try await makePastMeeting()
        let model = MeetingsViewModel(engine: nil, repository: repository, inserter: inserter)
        await model.loadPast()

        await model.copySelected()
        let copied = await inserter.inserted
        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(copied[0].contains("# Weekly sync"))
        XCTAssertTrue(copied[0].contains("**Harshit**"))
        XCTAssertTrue(copied[0].contains("_[System audio lost]_"))

        let markdown = try XCTUnwrap(model.markdownExport())
        XCTAssertTrue(String(decoding: markdown, as: UTF8.self).contains("Their reply."))
        let json = try XCTUnwrap(model.jsonExport())
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, 1)
    }

    func testRenameSpeakerUpdatesDocumentAndRepository() async throws {
        _ = try await makePastMeeting()
        let model = MeetingsViewModel(engine: nil, repository: repository, inserter: inserter)
        await model.loadPast()

        await model.renameSpeaker(id: "remote-1", label: "Alice")
        XCTAssertEqual(model.selectedDocument?.speakers.first { $0.id == "remote-1" }?.name, "Alice")
        XCTAssertTrue(model.selectedDocument?.turns.filter { $0.speakerID == "remote-1" }
            .allSatisfy { $0.speakerName == "Alice" } ?? false)
        let speakers = try await repository.speakers(session: SessionID("past-1"))
        XCTAssertEqual(speakers.first { $0.id == "remote-1" }?.label, "Alice")
    }

    func testPastSearchFiltersMeetings() async throws {
        _ = try await makePastMeeting(id: "a", title: "Weekly sync",
                                      startedAt: Date(timeIntervalSince1970: 100))
        _ = try await makePastMeeting(id: "b", title: "Design review",
                                      startedAt: Date(timeIntervalSince1970: 200))
        let model = MeetingsViewModel(engine: nil, repository: repository, inserter: inserter)
        model.pastQuery = "design"
        await model.loadPast()
        XCTAssertEqual(model.pastSessions.map(\.id.value), ["b"])
    }

    func testEventProjectionTracksPartialsLevelsAndCompletion() async throws {
        var clock = Date(timeIntervalSince1970: 2_000)
        let model = MeetingsViewModel(engine: nil, repository: repository, inserter: inserter,
                                      now: { clock })
        await model.handle(.state(.warming))
        XCTAssertEqual(model.state, .warming)
        await model.handle(.state(.recording))
        XCTAssertEqual(model.state, .recording)

        clock = clock.addingTimeInterval(3)
        model.tick()
        XCTAssertEqual(model.elapsedMs, 3_000)
        XCTAssertEqual(model.elapsedLabel, "0:03")

        await model.handle(.partial(.mic, "my update"))
        await model.handle(.partial(.system, "their reply"))
        await model.handle(.level(.mic, 0.4))
        await model.handle(.level(.system, 1.4))
        await model.handle(.notice("System audio lost."))
        XCTAssertEqual(model.micWordCount, 2)
        XCTAssertEqual(model.systemWordCount, 2)
        XCTAssertEqual(model.micLevels, [0.4])
        XCTAssertEqual(model.systemLevels, [1])
        XCTAssertEqual(model.notice, "System audio lost.")

        let document = MeetingDocument(sessionID: SessionID("live"), title: "Meeting",
                                       startedAt: clock, endedAt: clock, durationMs: 3_000,
                                       speakers: [], turns: [])
        await model.handle(.finished(SessionID("live"), document))
        XCTAssertEqual(model.state, .complete(SessionID("live")))
        XCTAssertEqual(model.selectedDocument?.title, "Meeting")
        XCTAssertEqual(model.elapsedMs, 3_000)
    }

    func testStartAndStopWithFakeEngine() async throws {
        let engine = makeEngine()
        let model = MeetingsViewModel(engine: engine, repository: repository, inserter: inserter)
        await model.start()
        XCTAssertEqual(model.state, .recording)
        XCTAssertTrue(model.isRecording)

        let stopped = await model.stop()
        let document = try XCTUnwrap(stopped)
        XCTAssertEqual(model.state, .complete(document.sessionID))
        XCTAssertTrue(document.turns.contains { $0.source == .mic })
        XCTAssertTrue(document.turns.contains { $0.source == .system })
        XCTAssertEqual(model.selectedDocument?.sessionID, document.sessionID)
        XCTAssertFalse(model.pastSessions.isEmpty)
        let stored = try await repository.session(document.sessionID)
        XCTAssertEqual(stored?.kind, .meeting)
    }

    func testCancelDiscardsMeeting() async throws {
        let engine = makeEngine()
        let model = MeetingsViewModel(engine: engine, repository: repository, inserter: inserter)
        await model.start()
        await model.cancel()
        XCTAssertEqual(model.state, .cancelled(nil))
        XCTAssertEqual(model.micPartial, "")
        XCTAssertEqual(model.elapsedMs, 0)
        let count = try await repository.sessionCount(kind: .meeting)
        XCTAssertEqual(count, 0)
    }
}
