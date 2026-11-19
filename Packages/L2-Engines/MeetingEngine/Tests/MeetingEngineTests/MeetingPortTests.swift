import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowTextPipeline
@testable import SuperflowMeetingEngine

/// Focused checks for the hex ideas ported into MeetingEngine: bounded echo evidence, per-lane
/// failure isolation, durable lost-stream markers, and export of clock-aligned labeled turns.
final class MeetingPortTests: XCTestCase {

    // MARK: - Echo evidence

    private func turn(_ index: Int, _ id: String, _ source: AudioSourceKind,
                      _ start: Int, _ end: Int, _ text: String) -> MeetingTurn {
        MeetingTurn(index: index, speakerID: id, speakerName: id, startMs: start, endMs: end,
                    text: text, rawText: text, source: source)
    }

    func testEchoNeedsAlignmentAndOrderedNearIdenticalWords() {
        let micText = "hello there everyone listening"
        let system = turn(1, "remote-1", .system, 0, 5_000, micText)
        XCTAssertTrue(MeetingEcho.isEcho(
            mic: turn(0, "self", .mic, 0, 5_000, micText), system: system))

        // Two people talking at the same time about different things is never echo.
        XCTAssertFalse(MeetingEcho.isEcho(
            mic: turn(0, "self", .mic, 0, 5_000, "please open the red door now"),
            system: turn(1, "remote-1", .system, 0, 5_000, "please close the blue window today")))

        // Equal words well outside the remote-to-mic delay window are a coincidence.
        XCTAssertFalse(MeetingEcho.isEcho(
            mic: turn(0, "self", .mic, 6_000, 11_000, micText), system: system))

        // Same words in a different order, and one-word coincidences, are not evidence.
        XCTAssertFalse(MeetingEcho.isEcho(
            mic: turn(0, "self", .mic, 0, 5_000, "there hello everyone listening"), system: system))
        XCTAssertFalse(MeetingEcho.isEcho(
            mic: turn(0, "self", .mic, 0, 5_000, "yes"),
            system: turn(1, "remote-1", .system, 0, 5_000, "yes")))

        // A shared sliver of time is not alignment either.
        XCTAssertFalse(MeetingEcho.isEcho(
            mic: turn(0, "self", .mic, 4_900, 5_000, micText),
            system: turn(1, "remote-1", .system, 0, 1_000, micText)))
        XCTAssertEqual(MeetingEcho.similarity("hello there", "hello there"), 1.0, accuracy: 0.001)
        XCTAssertLessThan(MeetingEcho.similarity("hello there", "there hello"), 0.6)
    }

    private func engineWithSilentSources() -> MeetingEngine {
        MeetingEngine(mic: ScriptedAudioSource(samples: []), system: ScriptedAudioSource(samples: []),
                      recognizer: FakeSpeechRecognizer(script: []), pipeline: TextPipeline(stages: []),
                      repository: InMemoryRepository(), journals: FakeJournalStore())
    }

    /// Drives both arrival orders directly through `persist`: mic-first exercises the
    /// system-arrives-later path, system-first the mic-arrives-later path.
    func testDedupeAppliedInBothArrivalOrders() async throws {
        for micFirst in [true, false] {
            for isEcho in [true, false] {
                let engine = engineWithSilentSources()
                let id = try await engine.start()
                let micText = isEcho ? "hello there everyone listening" : "please open the red door now"
                let systemText = isEcho ? "hello there everyone listening" : "please close the blue window today"
                let mic = RawSegment(text: micText, startSample: 0, endSample: 80_000, source: .mic)
                let system = RawSegment(text: systemText, startSample: 0, endSample: 80_000, source: .system)
                if micFirst {
                    await engine.persist(mic, source: .mic, session: id)
                    await engine.persist(system, source: .system, session: id)
                } else {
                    await engine.persist(system, source: .system, session: id)
                    await engine.persist(mic, source: .mic, session: id)
                }
                let stopped = await engine.stop()
                let doc = try XCTUnwrap(stopped)
                let real = doc.turns.filter { !$0.isGap }
                XCTAssertEqual(real.count, isEcho ? 1 : 2)
                // Echo evidence removes only the microphone duplicate: the remote/system turn is
                // always kept. With no echo evidence both lanes must survive (different speech),
                // so the all-system assertion applies only to the echo case.
                XCTAssertEqual(Set(real.map(\.source)), isEcho ? [.system] : [.mic, .system])
            }
        }
    }

    // MARK: - Per-lane failure isolation

    private func makeEngine(mic: any AudioSource, system: (any AudioSource)?,
                        recognizer: any SpeechRecognizer, repo: InMemoryRepository,
                        journals: FakeJournalStore, keepJournals: Bool = false) -> MeetingEngine {
        // `settings` sits after `journals` in the MeetingEngine initializer. Retention must be
        // requested explicitly: a normal stop() deletes journals unless keepJournals is set, so
        // asserting a degraded lane's audio remains inspectable requires passing it here.
        var settings = AppSettings.default
        settings.keepJournals = keepJournals
        return MeetingEngine(mic: mic, system: system, recognizer: recognizer,
                             pipeline: TextPipeline(stages: []), repository: repo, journals: journals,
                             settings: settings)
    }

    private func waitForNotice(_ substring: String, in engine: MeetingEngine) async throws {
        try await withDeadline(.seconds(5), label: "meeting notice") {
            for await event in engine.events {
                if case .notice(let message) = event, message.contains(substring) { return }
            }
        }
    }

    func testSystemRecogniserFailureKeepsMicTranscriptJournalAndCompletes() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let engine = makeEngine(mic: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .mic),
                            system: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .system),
                            recognizer: SelectiveRecognizer(failing: .system),
                            repo: repo, journals: journals, keepJournals: true)
        let id = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        let state = await engine.currentState
        XCTAssertEqual(state, .complete(id))
        XCTAssertTrue(doc.turns.contains { $0.source == .mic && !$0.isGap && $0.rawText.contains("mic words") })
        XCTAssertTrue(doc.turns.contains { $0.isGap && $0.rawText.contains(MeetingStreamLoss.systemTranscriptLost) })
        XCTAssertTrue(doc.notices.contains { $0.contains("recognition problem") })
        let stored = try await repo.segments(session: id)
        XCTAssertTrue(stored.contains { !$0.rawText.hasPrefix("[") && !$0.rawText.isEmpty })
        let systemSamples = await journals.sampleCount(session: id, source: .system)
        let micSamples = await journals.sampleCount(session: id, source: .mic)
        XCTAssertGreaterThan(systemSamples, 0)
        XCTAssertGreaterThan(micSamples, 0)
    }

    func testMicRecogniserFailureKeepsSystemTranscriptJournalAndCompletes() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let engine = makeEngine(mic: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .mic),
                            system: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .system),
                            recognizer: SelectiveRecognizer(failing: .mic),
                            repo: repo, journals: journals, keepJournals: true)
        let id = try await engine.start()
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        let state = await engine.currentState
        XCTAssertEqual(state, .complete(id))
        XCTAssertTrue(doc.turns.contains { $0.source == .system && !$0.isGap && $0.rawText.contains("remote words") })
        XCTAssertTrue(doc.turns.contains { $0.isGap && $0.rawText.contains(MeetingStreamLoss.micTranscriptLost) })
        let stored = try await repo.segments(session: id)
        XCTAssertTrue(stored.contains { $0.source == .system && !$0.rawText.hasPrefix("[") })
        let micSamples = await journals.sampleCount(session: id, source: .mic)
        XCTAssertGreaterThan(micSamples, 0)
    }

    func testInputFailureEventMarksOneGapAndKeepsTheOtherLane() async throws {
        let failing = EventFailingAudioSource(kind: .system, samples: Array(repeating: 0.2, count: 16_000))
        let engine = makeEngine(mic: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .mic),
                            system: failing,
                            recognizer: FakeSpeechRecognizer(script: ["mic words"],
                                                             samplesPerSegment: 80_000),
                            repo: InMemoryRepository(), journals: FakeJournalStore())
        _ = try await engine.start()
        try await waitForNotice("input loss", in: engine)
        let stopped = await engine.stop()
        let doc = try XCTUnwrap(stopped)
        XCTAssertTrue(doc.turns.filter { $0.isGap }.count == 1)
        XCTAssertTrue(doc.turns.contains { $0.isGap && $0.rawText.contains(MeetingStreamLoss.systemLost) })
        XCTAssertTrue(doc.turns.contains { $0.source == .mic && !$0.isGap })
    }

    // MARK: - Durable markers, ordering, export

    func testGapMarkersSurviveProjectionAndDroppedEchoDoesNot() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let record = SessionRecord(kind: .meeting, startedAt: started, modelProfile: "p", title: "Sync")
        let segments = [
            Segment(sessionID: record.id, index: 0, startMs: 0, endMs: 100,
                    speakerID: "self", source: .mic, rawText: "lost speech",
                    cleanupState: .skipped), // echo-dropped
            Segment(sessionID: record.id, index: 1, startMs: 100, endMs: 100,
                    speakerID: "mic", source: .mic,
                    rawText: MeetingStreamLoss.marker(MeetingStreamLoss.micTranscriptLost),
                    cleanupState: .skipped),
            Segment(sessionID: record.id, index: 2, startMs: 120, endMs: 220,
                    speakerID: "remote-1", source: .system, rawText: "remote words",
                    cleanedText: "remote words", cleanupState: .cleaned),
        ]
        let doc = MeetingDocumentProjection.make(record: record, segments: segments,
                                                 speakers: [SpeakerRecord(sessionID: record.id,
                                                                          id: "remote-1",
                                                                          label: "Priya", isSelf: false)])
        XCTAssertEqual(doc.turns.map { $0.index }, [1, 2])
        XCTAssertEqual(doc.turns[0].text, MeetingStreamLoss.micTranscriptLost)
        XCTAssertTrue(doc.turns[0].isGap)
        XCTAssertEqual(doc.turns[1].speakerName, "Priya")
    }

    func testTurnsOrderOnSharedClockWithStableSpeakerIDs() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let record = SessionRecord(kind: .meeting, startedAt: started, modelProfile: "p")
        let turns = [
            turn(4, "remote-2", .system, 2_000, 2_500, "second remote"),
            turn(2, "self", .mic, 1_000, 1_500, "you first"),
            turn(3, "remote-1", .system, 1_000, 1_500, "first remote"),
        ]
        let doc = MeetingDocumentProjection.make(record: record, turns: turns, notices: [],
                                                 endedAt: nil, durationMs: 2_500)
        XCTAssertEqual(doc.turns.map(\.index), [2, 3, 4])
        XCTAssertEqual(doc.turns.map(\.speakerID), ["self", "remote-1", "remote-2"])
        XCTAssertEqual(Set(doc.speakers.map(\.id)), ["self", "remote-1", "remote-2"])
    }

    func testExportCarriesTimestampsLabelsAndGapMarkers() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let record = SessionRecord(kind: .meeting, startedAt: started, modelProfile: "p", title: "Sync")
        let segments = [
            Segment(sessionID: record.id, index: 0, startMs: 61_000, endMs: 62_000,
                    speakerID: "self", source: .mic, rawText: "hello"),
            Segment(sessionID: record.id, index: 1, startMs: 62_000, endMs: 62_000,
                    speakerID: "system", source: .system,
                    rawText: MeetingStreamLoss.marker(MeetingStreamLoss.systemLost),
                    cleanupState: .skipped),
        ]
        let doc = MeetingDocumentProjection.make(record: record, segments: segments, speakers: [])
        let markdown = MeetingExport.markdown(doc, options: .deterministic)
        XCTAssertTrue(markdown.contains("**You** · 1:01"))
        XCTAssertTrue(markdown.contains("_[System audio lost]_"))

        let data = try MeetingExport.jsonData(doc, options: .deterministic)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try XCTUnwrap(root["segments"] as? [[String: Any]])
        XCTAssertEqual(parts[0]["start_ms"] as? Int, 61_000)
        XCTAssertEqual(parts[0]["end_ms"] as? Int, 62_000)
        XCTAssertEqual(parts[0]["speaker"] as? String, "You")
        XCTAssertEqual(parts[1]["text"] as? String, MeetingStreamLoss.systemLost)
        XCTAssertEqual(parts[1]["is_gap"] as? Bool, true)
    }

    func testSystemOffsetIsZeroUntilTheMonotonicClockMovesForward() {
        XCTAssertEqual(MeetingEngine.offsetSamples(from: nil, to: 1_000), 0)
        XCTAssertEqual(MeetingEngine.offsetSamples(from: 1_000, to: 1_000), 0)
        XCTAssertEqual(MeetingEngine.offsetSamples(from: 1_000, to: 500), 0)
        XCTAssertEqual(MeetingEngine.offsetSamples(from: 1_000, to: 250_000_000), 4_000)
    }
}

// MARK: - Local doubles

/// Sends a recognition failure on one lane only; the other lane behaves normally.
private actor SelectiveRecognizer: SpeechRecognizer {
    private let failing: AudioSourceKind
    init(failing: AudioSourceKind) { self.failing = failing }

    var isReady: Bool { true }
    func isPrepared(profile: String) async -> Bool { true }
    func warmUp(profile: String) async throws {}
    func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        if source == failing {
            return FailingRecognitionStream(reason: "lane stopped")
        }
        return FakeRecognitionStream(
            script: [source == .mic ? "mic words here" : "remote words here"],
            samplesPerSegment: 80_000, source: source)
    }
}

private final class FailingRecognitionStream: RecognitionStream, @unchecked Sendable {
    let events: AsyncStream<RecognitionEvent>
    private let continuation: AsyncStream<RecognitionEvent>.Continuation

    init(reason: String) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
        continuation.yield(.failure(reason))
        continuation.finish()
    }

    func feed(_ chunk: AudioChunk) async {}
    func finish() async {}
}

/// Yields a little audio, then fails its input event, leaving the other lane untouched.
private final class EventFailingAudioSource: AudioSource, @unchecked Sendable {
    let kind: AudioSourceKind
    private let samples: [Float]
    init(kind: AudioSourceKind, samples: [Float]) {
        self.kind = kind
        self.samples = samples
    }

    func start() async throws -> AudioStreams {
        let (stream, sampleContinuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        sampleContinuation.yield(AudioChunk(samples: samples, startSample: 0, source: kind))
        sampleContinuation.finish()
        eventContinuation.yield(.failed("scripted input loss"))
        eventContinuation.finish()
        return AudioStreams(samples: stream, events: events)
    }

    func stop() async {}
}
