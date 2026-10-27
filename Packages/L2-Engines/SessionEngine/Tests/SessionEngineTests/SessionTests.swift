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
                        inserter: RecordingInserter = RecordingInserter()) -> SessionEngine {
        SessionEngine(audio: audio, recognizer: recognizer, pipeline: pipeline(cleaner),
                      repository: repo, journals: journals, inserter: inserter)
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
}
