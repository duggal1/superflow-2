import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline
@testable import SuperflowSessionEngine

final class SessionTests: XCTestCase {
    private func pipeline(_ cleaner: FakeTextCleaner = FakeTextCleaner(.identity)) -> TextPipeline {
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.harperEnabled = false
        let deps = TextPipelineDependencies(cleaner: CleanupService(cleaner: cleaner))
        return TextPipelineBuilder.make(settings: settings, dependencies: deps)
    }

    private func engine(audio: ScriptedAudioSource = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000)),
                        recognizer: FakeSpeechRecognizer = FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 80_000),
                        cleaner: FakeTextCleaner = FakeTextCleaner(.identity),
                        repo: InMemoryRepository = InMemoryRepository(),
                        journals: FakeJournalStore = FakeJournalStore(),
                        inserter: RecordingInserter = RecordingInserter(),
                        deadline: Duration = .seconds(8)) -> SessionEngine {
        SessionEngine(audio: audio, recognizer: recognizer, pipeline: pipeline(cleaner),
                      repository: repo, journals: journals, inserter: inserter,
                      insertionDeadline: deadline)
    }

    func testStartRecordsAndStopInserts() async throws {
        let repo = InMemoryRepository()
        let inserter = RecordingInserter()
        let engine = engine(repo: repo, inserter: inserter)
        let id = try await engine.start()
        let state1 = await engine.currentState
        XCTAssertEqual(state1, .recording(.dictation))
        let outcome = await engine.stop()
        XCTAssertEqual(outcome?.sessionID, id)
        XCTAssertEqual(outcome?.wordCount, 4)
        XCTAssertEqual(outcome?.insertion, .pasted)
        let state2 = await engine.currentState
        XCTAssertEqual(state2, .complete(id))
        let inserted = await inserter.inserted
        XCTAssertEqual(inserted.count, 1)
        XCTAssertTrue(inserted[0].contains("Hello world"))
        let session = try await repo.session(id)
        XCTAssertEqual(session?.status, .complete)
        XCTAssertEqual(session?.wordCount, 4)
        let segments = try await repo.segments(session: id)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.map(\.index), [0, 1])
        XCTAssertTrue(segments.allSatisfy { $0.cleanupState == .cleaned })
    }

    func testCleanupPoolDrainsManyPersistedSegmentsInOrder() async throws {
        let count = 40
        let repo = InMemoryRepository()
        let inserter = RecordingInserter()
        let audio = ScriptedAudioSource(samples: Array(repeating: 0.2, count: count * 1_600))
        let recognizer = FakeSpeechRecognizer(script: ["segment one", "segment two"],
                                              samplesPerSegment: 1_600)
        let engine = engine(audio: audio, recognizer: recognizer, repo: repo, inserter: inserter)

        let id = try await engine.start()
        let outcome = await engine.stop()
        let segments = try await repo.segments(session: id)
        let inserted = await inserter.inserted

        XCTAssertEqual(segments.count, count)
        XCTAssertEqual(segments.map(\.index), Array(0..<count))
        XCTAssertTrue(segments.allSatisfy { $0.cleanupState == .cleaned })
        XCTAssertEqual(outcome?.text.components(separatedBy: "\n\n").count, count)
        XCTAssertEqual(inserted.first, outcome?.text)
    }

    func testCancelDiscardsEverything() async throws {
        let repo = InMemoryRepository()
        let inserter = RecordingInserter()
        let engine = engine(repo: repo, inserter: inserter)
        let id = try await engine.start()
        await engine.cancel()
        let state3 = await engine.currentState
        XCTAssertEqual(state3, .cancelled(id))
        let stored = try await repo.session(id)
        XCTAssertNil(stored)
        let inserted = await inserter.inserted
        XCTAssertTrue(inserted.isEmpty)
    }

    func testDoubleStartThrows() async throws {
        let engine = engine()
        _ = try await engine.start()
        do {
            _ = try await engine.start()
            XCTFail("expected invalid state")
        } catch {
            XCTAssertTrue(error is SuperflowError)
        }
        await engine.cancel()
    }

    func testCleanupFailureFallsBackToRawText() async throws {
        let engine = engine(cleaner: FakeTextCleaner(.fail))
        _ = try await engine.start()
        let outcome = await engine.stop()
        XCTAssertEqual(outcome?.cleanupState, .fallback)
        XCTAssertTrue(outcome?.text.lowercased().contains("hello world") ?? false)
    }

    /// A filler-only dictation cleans to a valid empty string. The cleaned row
    /// and the session stay empty; the raw filler must not be inserted.
    func testFillerOnlyCleanupStoresEmptyResultAndSkipsInsertion() async throws {
        let repo = InMemoryRepository()
        let inserter = RecordingInserter()
        let audio = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 80_000))
        let recognizer = FakeSpeechRecognizer(script: ["um"], samplesPerSegment: 80_000)
        let engine = engine(audio: audio, recognizer: recognizer, cleaner: FakeTextCleaner(.empty),
                            repo: repo, inserter: inserter)
        let id = try await engine.start()
        let outcome = await engine.stop()
        XCTAssertEqual(outcome?.text, "")
        XCTAssertEqual(outcome?.cleanupState, .cleaned)
        XCTAssertNil(outcome?.insertion)
        let segments = try await repo.segments(session: id)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].cleanedText, "")
        XCTAssertEqual(segments[0].cleanupState, .cleaned)
        let inserted = await inserter.inserted
        XCTAssertTrue(inserted.isEmpty)
    }

    func testNoSpeechCompletesWithoutInsertion() async throws {
        let audio = ScriptedAudioSource(samples: [])
        let inserter = RecordingInserter()
        let engine = engine(audio: audio, inserter: inserter)
        _ = try await engine.start()
        let outcome = await engine.stop()
        XCTAssertEqual(outcome?.text, "")
        XCTAssertNil(outcome?.insertion)
        let inserted = await inserter.inserted
        XCTAssertTrue(inserted.isEmpty)
    }

    func testWarmUpReturnsToIdle() async {
        let engine = engine()
        let ok = await engine.warmUp()
        XCTAssertTrue(ok)
        let state4 = await engine.currentState
        XCTAssertEqual(state4, .idle)
    }

    /// Launch prewarm must not claim the model is loading: the window maps
    /// `.warming` to a visible "Loading model" banner.
    func testPrewarmLoadsWithoutEnteringWarming() async {
        let recognizer = FakeSpeechRecognizer()
        let engine = engine(recognizer: recognizer)
        let ok = await engine.prewarm()
        XCTAssertTrue(ok)
        let state = await engine.currentState
        XCTAssertEqual(state, .idle)
        let prepared = await recognizer.isPrepared(profile: AppSettings.default.asrProfile)
        XCTAssertTrue(prepared)
    }

    func testWarmUpFailureStillAllowsStart() async throws {
        let engine = engine(recognizer: FakeSpeechRecognizer(failWarmUp: true))
        let ok = await engine.warmUp()
        XCTAssertFalse(ok)
        let state5 = await engine.currentState
        XCTAssertEqual(state5, .idle)
    }

    func testInsertionBlockedStillCompletesAndKeepsHistory() async throws {
        let repo = InMemoryRepository()
        let inserter = RecordingInserter()
        await inserter.setOutcome(.blockedSecureField)
        let engine = engine(repo: repo, inserter: inserter)
        let id = try await engine.start()
        let outcome = await engine.stop()
        XCTAssertEqual(outcome?.insertion, .blockedSecureField)
        let state6 = await engine.currentState
        XCTAssertEqual(state6, .complete(id))
        let session = try await repo.session(id)
        XCTAssertEqual(session?.status, .complete)
    }

    func testEventsIncludePartialAndFinished() async throws {
        let engine = engine()
        let collector = Task { () -> [SessionEvent] in
            var out: [SessionEvent] = []
            for await event in engine.events {
                out.append(event)
                if case .finished = event { break }
            }
            return out
        }
        _ = try await engine.start()
        _ = await engine.stop()
        let events = await collector.value
        XCTAssertTrue(events.contains { if case .partial = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .finished = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .state(.complete) = $0 { true } else { false } })
    }

    func testJournalIsDeletedAfterStop() async throws {
        let journals = FakeJournalStore()
        let engine = engine(journals: journals)
        _ = try await engine.start()
        _ = await engine.stop()
        let count = await journals.sampleCount(session: "x", source: .mic)
        XCTAssertEqual(count, 0)
    }

    func testJournalDegradationIsSurfacedOnce() async throws {
        let journals = FakeJournalStore()
        await journals.setDegradeWrites(true)
        let engine = engine(journals: journals)
        let collector = Task { () -> [SessionEvent] in
            var out: [SessionEvent] = []
            for await event in engine.events {
                out.append(event)
                if case .finished = event { break }
            }
            return out
        }
        _ = try await engine.start()
        _ = await engine.stop()
        let events = await collector.value
        let notices = events.compactMap { event -> String? in
            if case .notice(let text) = event { return text }
            return nil
        }
        XCTAssertEqual(notices.filter { $0.contains("Audio journal stopped") }.count, 1,
                       "the user should be warned exactly once per session")
    }

    func testAudioStartFailureMarksFailed() async {
        let engine = engine(audio: ScriptedAudioSource(samples: [], failStart: true))
        do {
            _ = try await engine.start()
            XCTFail("expected failure")
        } catch {
            let state = await engine.currentState
            guard case .failed = state else {
                return XCTFail("state was \(state)")
            }
        }
    }

    /// A full disk must fail the start rather than recording with no durable journal.
    func testDiskFullStartFailsInsteadOfRecordingSilently() async throws {
        let journals = FakeJournalStore()
        await journals.setShouldFail(true)
        let audio = ScriptedAudioSource(samples: Array(repeating: 0.2, count: 16_000))
        let engine = engine(audio: audio, journals: journals)
        do {
            _ = try await engine.start()
            XCTFail("expected disk-full to fail the start")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .diskFull)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let state = await engine.currentState
        guard case .failed = state else {
            return XCTFail("state was \(state)")
        }
        // Capture must never begin when the journal cannot be opened.
        XCTAssertEqual(audio.startCount, 0)
        // A failed start must not leave a live input stream running.
        XCTAssertEqual(audio.stopCount, 1)
    }

    /// The adapter must see the frontmost app before warm-up so Chromium/Electron
    /// have the whole recording to expose their Accessibility tree.
    func testStartPreparesBeforeWarmUpAndStopInserts() async throws {
        let log = OrderLog()
        let inserter = RecordingInserter()
        await inserter.setEventLog { await log.append($0) }
        let recognizer = FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 80_000)
        await recognizer.setOnWarmUp { await log.append("warmup") }

        let engine = engine(recognizer: recognizer, inserter: inserter)
        _ = try await engine.start()
        _ = await engine.stop()

        let events = await log.events
        XCTAssertEqual(events, ["frontmost", "prepare", "warmup", "insert:auto"])
        let prepares = await inserter.prepareCalls
        XCTAssertEqual(prepares, 1)
    }

    /// A stuck insert must not leave the user with no copy: the deadline path
    /// writes the transcript with `.clipboardOnly` before claiming it is there.
    func testInsertionDeadlineFallsBackToClipboardOnly() async throws {
        let inserter = RecordingInserter()
        await inserter.setAutoDelay(ms: 300)
        let engine = engine(inserter: inserter, deadline: .milliseconds(10))

        _ = try await engine.start()
        let outcome = await engine.stop()

        guard case .clipboardOnly = outcome?.insertion else {
            return XCTFail("expected clipboardOnly fallback, got \(String(describing: outcome?.insertion))")
        }
        let events = await inserter.events
        XCTAssertTrue(events.contains("insert:clipboardOnly"), "events: \(events)")
    }

    /// "Warming up" has to mean a model load, not every key press. The first session
    /// is cold and announces it; the second finds the profile resident and starts
    /// silently, which is what made the app feel slow.
    func testOnlyAColdSessionAnnouncesWarming() async throws {
        let recognizer = FakeSpeechRecognizer(script: ["hello world"], samplesPerSegment: 80_000)
        let engine = engine(recognizer: recognizer)

        let cold = Task { () -> [SessionEvent] in
            var out: [SessionEvent] = []
            for await event in engine.events {
                out.append(event)
                if case .finished = event { break }
            }
            return out
        }
        try await Task.sleep(for: .milliseconds(30))
        _ = try await engine.start()
        _ = await engine.stop()
        let coldEvents = await cold.value
        XCTAssertTrue(coldEvents.contains { if case .state(.warming) = $0 { true } else { false } },
                      "a cold start must announce the model load")

        let profile = AppSettings.default.asrProfile
        let prepared = await recognizer.isPrepared(profile: profile)
        XCTAssertTrue(prepared, "the first session must leave the profile resident")

        let warm = Task { () -> [SessionEvent] in
            var out: [SessionEvent] = []
            for await event in engine.events {
                out.append(event)
                if case .finished = event { break }
            }
            return out
        }
        try await Task.sleep(for: .milliseconds(30))
        _ = try await engine.start()
        _ = await engine.stop()
        let warmEvents = await warm.value
        XCTAssertFalse(warmEvents.contains { if case .state(.warming) = $0 { true } else { false } },
                       "a resident profile must not announce warming")
        XCTAssertTrue(warmEvents.contains { if case .state(.recording) = $0 { true } else { false } })
    }

    /// Losing a clip is a bug the owner must hear about. `try?` around the archive
    /// writer turned that failure into silence, so a session could record with no
    /// audio anywhere and nothing said. The notice is the contract now.
    func testArchiveFailureIsReportedInsteadOfDropped() async throws {
        let engine = SessionEngine(audio: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 16_000)),
                                   recognizer: FakeSpeechRecognizer(script: ["hello world"],
                                                                    samplesPerSegment: 8_000),
                                   pipeline: pipeline(), repository: InMemoryRepository(),
                                   journals: FakeJournalStore(), inserter: RecordingInserter(),
                                   archive: FailingArchiveStore())
        let notices = NoticeLog()
        let consumer = Task { for await event in engine.events { await notices.add(event) } }
        _ = try await engine.start()
        try await Task.sleep(for: .milliseconds(50))
        let messages = await notices.text
        consumer.cancel()
        XCTAssertTrue(messages.contains("Audio could not be archived"), messages)
    }
}

actor NoticeLog {
    private(set) var text = ""
    func add(_ event: SessionEvent) {
        if case .notice(let message) = event { text += message + "\n" }
    }
}

/// Shared ordered log for assertions that span two test doubles.
actor OrderLog {
    private(set) var events: [String] = []
    func append(_ event: String) { events.append(event) }
}

/// An archive that cannot open a file, standing in for a read-only or full disk.
struct FailingArchiveStore: AudioArchiveStore {
    struct Failure: LocalizedError {
        var errorDescription: String? { "the archive directory is unavailable" }
    }
    func makeWriter(session: SessionID) async throws -> any AudioArchiveWriter { throw Failure() }
    func delete(session: SessionID) async {}
    func sweep(olderThanDays days: Int?) async {}
}
