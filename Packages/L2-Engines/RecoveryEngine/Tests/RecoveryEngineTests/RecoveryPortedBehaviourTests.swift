import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowRecoveryEngine

/// A recognizer that stamps a committed segment before blocking on a gate. It lets a test close a
/// recovery generation while a callback from that generation is still in flight.
private final class GatedLateRecognizer: SpeechRecognizer, @unchecked Sendable {
    let isReady = true
    private let entered: AsyncGate
    private let release: AsyncGate
    private let lateText: String

    init(entered: AsyncGate, release: AsyncGate, lateText: String = "STALE") {
        self.entered = entered
        self.release = release
        self.lateText = lateText
    }

    func warmUp(profile: String) async throws {}
    func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        await entered.open()
        return GatedLateStream(release: release, lateText: lateText, source: source)
    }
}

private final class GatedLateStream: RecognitionStream, @unchecked Sendable {
    let events: AsyncStream<RecognitionEvent>
    private let continuation: AsyncStream<RecognitionEvent>.Continuation
    private let release: AsyncGate
    private let lateText: String
    private let source: AudioSourceKind

    init(release: AsyncGate, lateText: String, source: AudioSourceKind) {
        (events, continuation) = AsyncStream<RecognitionEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.release = release
        self.lateText = lateText
        self.source = source
    }

    func feed(_ chunk: AudioChunk) async {
        continuation.yield(.committed(RawSegment(text: lateText, startSample: chunk.startSample,
                                                  endSample: chunk.endSample, source: source)))
        await release.wait()
    }

    func finish() async { continuation.finish() }
}

/// Fails recognition only on the named lane, by emitting a `.failure` event (a soft failure) rather
/// than throwing — exactly the "one dependency is down" shape.
private struct OneLaneFailingRecognizer: SpeechRecognizer {
    let isReady = true
    let failing: AudioSourceKind
    func warmUp(profile: String) async throws {}
    func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        FakeRecognitionStream(script: [source == .mic ? "mic words" : "system words"],
                              samplesPerSegment: 1_600, source: source,
                              failEvery: source == failing ? 1 : 0)
    }
}

final class RecoveryPortedBehaviourTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws { root = RecoveryTestSupport.tempRoot("ported") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func session(kind: SessionKind = .dictation) -> SessionRecord {
        SessionRecord(kind: kind, status: .recording, modelProfile: ModelProfile.default.id)
    }

    private func chunks(_ count: Int, source: AudioSourceKind = .mic) -> [AudioChunk] {
        (0..<count).map { i in
            AudioChunk(samples: Array(repeating: 0.2, count: 1_600),
                       startSample: Int64(i * 1_600), source: source)
        }
    }

    // MARK: - R1: generation fence

    func testAdvancingEpochFencesLateCallbacks() async {
        let fence = RecoveryEpochFence()
        let first = await fence.token
        let second = await fence.advance()
        let firstCurrent = await fence.isCurrent(first)
        let secondCurrent = await fence.isCurrent(second)
        XCTAssertLessThan(first, second)
        XCTAssertFalse(firstCurrent, "a closed generation must be fenced")
        XCTAssertTrue(secondCurrent, "the new generation is the only live one")
    }

    func testSessionGateRejectsStaleEpochAndDuplicateSegmentClaims() async {
        let gate = RecoverySessionGate()
        let firstPhase = await gate.currentPhase
        XCTAssertEqual(firstPhase, .idle)

        let first = await gate.begin()
        let duplicateRun = await gate.begin()
        XCTAssertNotNil(first)
        XCTAssertNil(duplicateRun, "a second begin must not start a duplicate recovery")

        let key = "session|mic|0|1600"
        let firstClaim = await gate.claimSegment(key)
        let secondClaim = await gate.claimSegment(key)
        XCTAssertTrue(firstClaim)
        XCTAssertFalse(secondClaim, "the same segment must not be claimed twice")

        var firstActive = false
        if let first { firstActive = await gate.isActive(first) }
        XCTAssertTrue(firstActive)

        await gate.cancel()
        let cancelledPhase = await gate.currentPhase
        var staleActive = false
        if let first { staleActive = await gate.isActive(first) }
        XCTAssertEqual(cancelledPhase, .cancelled)
        XCTAssertFalse(staleActive, "cancel must fence the abandoned generation")

        let second = await gate.rearm()
        let idlePhase = await gate.currentPhase
        var stillStale = true
        if let first { stillStale = await gate.isActive(first) }
        XCTAssertEqual(idlePhase, .idle)
        XCTAssertGreaterThan(second, first!)
        XCTAssertFalse(stillStale, "rearm must not revive an old generation")
        // Epoch fencing: rearm returns the gate to idle, so no run is active and no segment may be
        // claimed until a fresh begin() opens a new generation. This is stricter than the old
        // expectation that a claim could succeed straight after rearm: a late callback from the
        // cancelled run can never append a row, and no claim is accepted outside an active run.
        let idleClaim = await gate.claimSegment(key)
        XCTAssertFalse(idleClaim, "no segment may be claimed while the gate is idle after rearm")
        let reopened = await gate.begin()
        XCTAssertNotNil(reopened, "a fresh run may start after rearm")
        let freshClaim = await gate.claimSegment(key)
        XCTAssertTrue(freshClaim, "a new generation clears per-run bookkeeping, not durable rows")
    }

    // MARK: - R2: degrade only the failing dependency

    func testFailingSystemLaneDoesNotAbortMicLane() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let meeting = session(kind: .meeting)
        try await repo.createSession(meeting)
        for chunk in chunks(2, source: .mic) { await journals.record(chunk) }
        for chunk in chunks(2, source: .system) { await journals.record(chunk) }

        let engine = RecoveryTestSupport.engine(repository: repo, journals: journals,
                                                recognizer: OneLaneFailingRecognizer(failing: .system),
                                                root: root)
        let report = await engine.recover()

        XCTAssertEqual(report.recovered, 1, "the healthy lane still finalizes the session")
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(report.degradedSources, [.system])
        let segments = try await repo.segments(session: meeting.id)
        XCTAssertTrue(segments.contains { $0.source == .mic })
        XCTAssertFalse(segments.contains { $0.source == .system })
        let status = try await repo.session(meeting.id)?.status
        XCTAssertEqual(status, .recovered)
        // Nothing was discarded: the failing lane's journal stays for inspection.
        XCTAssertTrue(report.discarded.isEmpty)
        let systemSamples = await journals.sampleCount(session: meeting.id, source: .system)
        XCTAssertEqual(systemSamples, 3_200)
    }

    // MARK: - R3: cancel/rearm without phantom rows

    func testCancelAndRearmProduceNoPhantomRowsOrDuplicateSegments() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let record = session()
        try await repo.createSession(record)
        for chunk in chunks(2) { await journals.record(chunk) }

        let entered = AsyncGate()
        let release = AsyncGate()
        let gated = GatedLateRecognizer(entered: entered, release: release)
        let engine = RecoveryTestSupport.engine(repository: repo, journals: journals,
                                                recognizer: gated, root: root)

        let firstRun = Task { await engine.recover() }
        await entered.wait()
        await engine.cancel()
        _ = await engine.rearm()
        await release.open()
        let cancelled = await firstRun.value

        XCTAssertTrue(cancelled.notices.contains { $0.contains("was cancelled") },
                      "cancel must be reported, not hidden: \(cancelled.notices)")
        let rowsAfterCancel = try await repo.segments(session: record.id)
        XCTAssertTrue(rowsAfterCancel.isEmpty, "cancel must not commit a late callback from its generation")
        let statusAfterCancel = try await repo.session(record.id)?.status
        XCTAssertEqual(statusAfterCancel, .recording, "cancel must not fabricate a finalized session")
        let samplesAfterCancel = await journals.sampleCount(session: record.id, source: .mic)
        XCTAssertEqual(samplesAfterCancel, 3_200, "cancel must never delete the journal")

        // A fresh run after rearm works, and cannot be polluted by the cancelled run's callback.
        let healed = RecoveryTestSupport.engine(repository: repo, journals: journals,
                                                recognizer: FakeSpeechRecognizer(script: ["fresh"],
                                                                                 samplesPerSegment: 1_600),
                                                root: root)
        let second = await healed.recover()
        XCTAssertEqual(second.recovered, 1)
        let rows = try await repo.segments(session: record.id)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.rawText == "fresh" })
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "no duplicate segment rows")
    }

    // MARK: - R4: explicit gap markers

    func testJournalDiscontinuityIsMarkedNotSilentlyBridged() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let record = session()
        try await repo.createSession(record)
        // Samples 1_600..3_200 are missing from the journal entirely.
        await journals.record(AudioChunk(samples: Array(repeating: 0.1, count: 1_600),
                                         startSample: 0, source: .mic))
        await journals.record(AudioChunk(samples: Array(repeating: 0.1, count: 1_600),
                                         startSample: 3_200, source: .mic))

        let engine = RecoveryTestSupport.engine(repository: repo, journals: journals,
                                                recognizer: FakeSpeechRecognizer(samplesPerSegment: 1_600),
                                                root: root)
        let report = await engine.recover()

        XCTAssertEqual(report.gaps.count, 1)
        let gap = try XCTUnwrap(report.gaps.first)
        XCTAssertEqual(gap.sessionID, record.id)
        XCTAssertEqual(gap.source, .mic)
        XCTAssertEqual(gap.startSample, 1_600)
        XCTAssertEqual(gap.endSample, 3_200)
        XCTAssertEqual(gap.samples, 1_600)
        XCTAssertTrue(report.notices.contains { $0.contains("lost 1600 samples") })

        let ledger = RecoveryLedger(root: root.appendingPathComponent("State", isDirectory: true))
        let records = (try? await ledger.read())?.records ?? []
        XCTAssertTrue(records.contains { $0.kind == .gapDetected && $0.samplePosition == 1_600 },
                      "a gap must be durable, not just an in-memory notice")
    }
}
