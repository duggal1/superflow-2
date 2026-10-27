import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline
@testable import SuperflowMeetingEngine

final class MeetingTests: XCTestCase {
    private func pipeline() -> TextPipeline {
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.harperEnabled = false
        return TextPipelineBuilder.make(settings: settings,
                                        dependencies: TextPipelineDependencies(cleaner: CleanupService(cleaner: FakeTextCleaner(.identity))))
    }

    private func audio(_ kind: AudioSourceKind, fail: Bool = false) -> ScriptedAudioSource {
        ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: kind, failStart: fail)
    }

    private func engine(mic: ScriptedAudioSource? = nil, system: ScriptedAudioSource? = nil,
                        recognizer: FakeSpeechRecognizer? = nil,
                        repo: InMemoryRepository = InMemoryRepository(),
                        journals: FakeJournalStore = FakeJournalStore()) -> MeetingEngine {
        let recognizer = recognizer ?? FakeSpeechRecognizer(
            script: ["hello"],
            scriptsBySource: [.mic: ["mic only words"], .system: ["remote words here"]],
            samplesPerSegment: 80_000)
        return MeetingEngine(mic: mic ?? audio(.mic), system: system ?? audio(.system),
                             recognizer: recognizer, pipeline: pipeline(),
                             repository: repo, journals: journals)
    }

    func testTwoSourcesMergeWithLabels() async throws {
        let repo = InMemoryRepository()
        let engine = engine(repo: repo)
        let id = try await engine.start()
        let document = await engine.stop()
        let doc = try XCTUnwrap(document)
        XCTAssertEqual(doc.sessionID, id)
        XCTAssertEqual(doc.turns.count, 4)
        XCTAssertTrue(doc.turns.contains { $0.speakerID == "self" && $0.text.contains("Mic only") })
        XCTAssertTrue(doc.turns.contains { $0.speakerID == "remote-1" && $0.text.contains("Remote words") })
        XCTAssertEqual(Set(doc.speakers.map(\.id)), ["self", "remote-1"])
        XCTAssertEqual(doc.speakers.first { $0.isSelf }?.name, "You")
        XCTAssertEqual(doc.speakers.first { $0.id == "remote-1" }?.name, "Speaker 1")
        let segments = try await repo.segments(session: id)
        XCTAssertEqual(segments.count, 4)
        XCTAssertTrue(segments.contains { $0.source == .system && $0.speakerID == "remote-1" })
        let state = await engine.currentState
        XCTAssertEqual(state, .complete(id))
    }

    func testEchoDedupeDropsMicSegments() async throws {
        let recognizer = FakeSpeechRecognizer(
            script: ["hello there everyone"],
            scriptsBySource: [.mic: ["hello there everyone"], .system: ["hello there everyone"]],
            samplesPerSegment: 80_000)
        let engine = engine(recognizer: recognizer)
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        XCTAssertEqual(doc.turns.count, 2)
        XCTAssertTrue(doc.turns.allSatisfy { $0.source == .system })
        XCTAssertEqual(Set(doc.speakers.map(\.id)), ["remote-1"])
    }

    func testSystemFailureContinuesMicWithGap() async throws {
        let engine = engine(system: audio(.system, fail: true))
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        XCTAssertTrue(doc.notices.contains { $0.contains("System audio unavailable") })
        XCTAssertTrue(doc.turns.contains { $0.isGap })
        XCTAssertTrue(doc.turns.contains { $0.source == .mic && !$0.isGap })
    }

    func testNoSystemSourceStillRecordsMic() async throws {
        let engine = MeetingEngine(mic: audio(.mic), system: nil,
                                   recognizer: FakeSpeechRecognizer(script: ["mic words"], samplesPerSegment: 80_000),
                                   pipeline: pipeline(), repository: InMemoryRepository(),
                                   journals: FakeJournalStore())
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        XCTAssertTrue(doc.turns.contains { $0.isGap })
        XCTAssertTrue(doc.turns.contains { $0.source == .mic && !$0.isGap })
    }

    func testCancelDiscardsMeeting() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let engine = engine(repo: repo, journals: journals)
        let id = try await engine.start()
        await engine.cancel()
        let state = await engine.currentState
        XCTAssertEqual(state, .cancelled(id))
        let stored = try await repo.session(id)
        XCTAssertNil(stored)
        let remaining = await journals.sampleCount(session: id, source: .system)
        XCTAssertEqual(remaining, 0)
    }

    func testRenameSpeakerAfterStop() async throws {
        let engine = engine()
        _ = try await engine.start()
        _ = await engine.stop()
        await engine.renameSpeaker(id: "remote-1", label: "Alice")
        let current = await engine.currentDocument
        let doc = try XCTUnwrap(current)
        XCTAssertEqual(doc.speakers.first { $0.id == "remote-1" }?.name, "Alice")
        XCTAssertTrue(doc.turns.filter { $0.speakerID == "remote-1" }.allSatisfy { $0.speakerName == "Alice" })
    }

    func testMarkdownExport() async throws {
        let engine = engine()
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        let markdown = MeetingExport.markdown(doc)
        XCTAssertTrue(markdown.hasPrefix("# Meeting"))
        XCTAssertTrue(markdown.contains("**Participants:** You, Speaker 1"))
        XCTAssertTrue(markdown.contains("**You** · 0:00"))
        XCTAssertTrue(markdown.contains("Mic only words"))
    }

    func testJSONExportSchema() async throws {
        let engine = engine()
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        let data = try MeetingExport.jsonData(doc)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        let meeting = try XCTUnwrap(root["meeting"] as? [String: Any])
        XCTAssertNotNil(meeting["started_at"])
        XCTAssertNotNil(meeting["duration_ms"])
        let speakers = try XCTUnwrap(root["speakers"] as? [[String: Any]])
        XCTAssertTrue(speakers.contains { $0["is_self"] as? Bool == true })
        let segments = try XCTUnwrap(root["segments"] as? [[String: Any]])
        XCTAssertFalse(segments.isEmpty)
        XCTAssertNotNil(segments[0]["start_ms"])
        XCTAssertNotNil(segments[0]["end_ms"])
        XCTAssertNotNil(segments[0]["raw_text"])
        XCTAssertNotNil(segments[0]["speaker"])
    }

    func testEmptyMeetingCompletes() async throws {
        let mic = ScriptedAudioSource(samples: [], kind: .mic)
        let system = ScriptedAudioSource(samples: [], kind: .system)
        let engine = MeetingEngine(mic: mic, system: system,
                                   recognizer: FakeSpeechRecognizer(), pipeline: pipeline(),
                                   repository: InMemoryRepository(), journals: FakeJournalStore())
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        XCTAssertTrue(doc.turns.isEmpty)
        XCTAssertEqual(doc.durationMs, 0)
    }

    func testMicFailureFailsStart() async {
        let engine = engine(mic: audio(.mic, fail: true))
        do {
            _ = try await engine.start()
            XCTFail("expected failure")
        } catch {
            let state = await engine.currentState
            guard case .failed = state else { return XCTFail("state was \(state)") }
        }
    }

    /// A full disk on the microphone lane must fail the whole meeting start.
    func testMicDiskFullFailsStart() async {
        let journals = FakeJournalStore()
        await journals.setFailSources([.mic])
        let engine = engine(journals: journals)
        do {
            _ = try await engine.start()
            XCTFail("expected disk-full to fail the start")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .diskFull)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let state = await engine.currentState
        guard case .failed = state else { return XCTFail("state was \(state)") }
    }

    /// A full disk on the system lane is global, not a source glitch: it must fail the start
    /// rather than silently degrading to microphone-only capture with no system journal.
    func testSystemDiskFullFailsStartRatherThanDegrading() async {
        let journals = FakeJournalStore()
        await journals.setFailSources([.system])
        let engine = engine(journals: journals)
        do {
            _ = try await engine.start()
            XCTFail("expected disk-full to fail the start")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .diskFull)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let state = await engine.currentState
        guard case .failed = state else { return XCTFail("state was \(state)") }
    }

    func testSimilarityMetric() {
        XCTAssertEqual(MeetingTextSimilarity.ratio("hello there", "hello there"), 1.0, accuracy: 0.001)
        XCTAssertEqual(MeetingTextSimilarity.ratio("hello there", "goodbye now"), 0.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(MeetingTextSimilarity.ratio("hello there everyone", "hello there everybody"), 0.5)
    }

    // MARK: - Shared clock

    func testSystemSourceIsMappedOntoTheSharedClock() async throws {
        let clock = SteppingClock(stepNs: 250_000_000)
        let journals = FakeJournalStore()
        var settings = AppSettings.default
        settings.keepJournals = true
        let engine = MeetingEngine(
            mic: audio(.mic), system: audio(.system),
            recognizer: FakeSpeechRecognizer(script: ["mic words"],
                                             scriptsBySource: [.system: ["remote words"]],
                                             samplesPerSegment: 80_000),
            pipeline: pipeline(), repository: InMemoryRepository(), journals: journals,
            settings: settings,
            clock: clock)
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        let system = doc.turns.filter { $0.source == .system && !$0.isGap }
        XCTAssertFalse(system.isEmpty)
        XCTAssertEqual(system.map(\.startMs).min(), 250)
        XCTAssertEqual(system.map(\.endMs).max(), 10_250)
        let chunks = await journals.chunks[.system] ?? []
        XCTAssertEqual(chunks.first?.startSample, 4_000)
        let mic = doc.turns.filter { $0.source == .mic }
        XCTAssertEqual(mic.map(\.startMs).min(), 0)
    }

    // MARK: - Bounded memory

    func testSixtyMinuteMeetingKeepsResidentMemoryBounded() async throws {
        let interval = 5 * sampleRate
        let mic = TimedAudioSource(kind: .mic, chunkCount: 723, intervalSamples: interval)
        let system = TimedAudioSource(kind: .system, chunkCount: 723, intervalSamples: interval)
        let recognizer = FakeSpeechRecognizer(
            script: ["mic words"], scriptsBySource: [.system: ["remote words"]],
            samplesPerSegment: interval)
        let repo = InMemoryRepository()
        let engine = MeetingEngine(mic: mic, system: system, recognizer: recognizer,
                                   pipeline: pipeline(), repository: repo,
                                   journals: FakeJournalStore())
        _ = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        XCTAssertGreaterThanOrEqual(doc.durationMs, 3_600_000)
        XCTAssertGreaterThan(doc.turns.count, 1_000)
        let resident = await engine.residentTurns.count
        XCTAssertLessThanOrEqual(resident, MeetingEngine.residentTurnLimit)
        let stored = try await repo.segments(session: doc.sessionID)
        XCTAssertEqual(stored.count, doc.turns.count)
    }

}

/// Advances 250 ms on every monotonic read, so the second source starts one step after the first.
private final class SteppingClock: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var ns: UInt64 = 0
    private let step: UInt64

    init(stepNs: UInt64) { step = stepNs }

    func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(ns) / 1e9) }

    func monotonicNs() -> UInt64 {
        lock.withLock {
            let value = ns
            ns += step
            return value
        }
    }
}

/// Emits sparse chunks whose timestamps advance by `intervalSamples`. Sample payloads stay tiny,
/// so a simulated hour does not allocate an hour of audio.
private final class TimedAudioSource: AudioSource, @unchecked Sendable {
    let kind: AudioSourceKind
    private let chunkCount: Int
    private let intervalSamples: Int
    private let chunkSamples: Int

    init(kind: AudioSourceKind, chunkCount: Int, intervalSamples: Int, chunkSamples: Int = 1_600) {
        self.kind = kind
        self.chunkCount = chunkCount
        self.intervalSamples = intervalSamples
        self.chunkSamples = chunkSamples
    }

    func start() async throws -> AudioStreams {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(4_096))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(8))
        let payload = Array(repeating: Float(0.1), count: chunkSamples)
        for index in 0..<chunkCount {
            continuation.yield(AudioChunk(samples: payload,
                                          startSample: Int64(index * intervalSamples),
                                          source: kind))
        }
        continuation.finish()
        eventContinuation.yield(.stopped)
        eventContinuation.finish()
        return AudioStreams(samples: stream, events: events)
    }

    func stop() async {}
}
