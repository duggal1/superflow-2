import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
@testable import SuperflowRecoveryEngine

final class RecoveryTests: XCTestCase {
    private func session(kind: SessionKind = .dictation, profile: String = ModelProfile.parakeetEOU120M.id) -> SessionRecord {
        SessionRecord(kind: kind, status: .recording, modelProfile: profile)
    }

    private func chunks(_ count: Int, source: AudioSourceKind = .mic) -> [AudioChunk] {
        (0..<count).map { i in
            AudioChunk(samples: Array(repeating: 0.1, count: 1_600), startSample: Int64(i * 1_600), source: source)
        }
    }

    func testRecoversJournaledAudioAndFinalizes() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let s = session()
        try await repo.createSession(s)
        for chunk in chunks(2) { await journals.record(chunk) }
        let recognizer = FakeSpeechRecognizer(script: ["recovered words"], samplesPerSegment: 1_600)
        let engine = RecoveryEngine(repository: repo, journals: journals, recognizer: recognizer,
                                    clock: SystemTimeSource())
        let report = await engine.recover()
        XCTAssertEqual(report.scanned, 1)
        XCTAssertEqual(report.recovered, 1)
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(report.samplesReplayed, 3_200)
        XCTAssertGreaterThan(report.segmentsAdded, 0)
        XCTAssertEqual(report.recoveredTranscripts.first?.text, "recovered words recovered words")
        let after = try await repo.session(s.id)
        XCTAssertEqual(after?.status, .recovered)
        let segments = try await repo.segments(session: s.id)
        XCTAssertFalse(segments.isEmpty)
        XCTAssertEqual(segments.map(\.index), Array(0..<segments.count))
        XCTAssertTrue(segments.allSatisfy { $0.cleanupState == .pending })
        let remaining = await journals.sampleCount(session: s.id, source: .mic)
        XCTAssertEqual(remaining, 0)
    }

    func testKeepsExistingCommittedSegments() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let s = session()
        try await repo.createSession(s)
        try await repo.appendSegment(Segment(sessionID: s.id, index: 0, startMs: 0, endMs: 100,
                                             source: .mic, rawText: "already committed"))
        for chunk in chunks(2) { await journals.record(chunk) }
        let engine = RecoveryEngine(repository: repo, journals: journals,
                                    recognizer: FakeSpeechRecognizer(script: ["new"], samplesPerSegment: 1_600))
        _ = await engine.recover()
        let segments = try await repo.segments(session: s.id)
        XCTAssertEqual(segments.first?.rawText, "already committed")
        XCTAssertEqual(segments.first?.index, 0)
        XCTAssertGreaterThan(segments.count, 1)
    }

    func testNoJournalStillFinalizes() async throws {
        let repo = InMemoryRepository()
        let s = session()
        try await repo.createSession(s)
        let engine = RecoveryEngine(repository: repo, journals: FakeJournalStore(),
                                    recognizer: FakeSpeechRecognizer())
        let report = await engine.recover()
        XCTAssertEqual(report.recovered, 1)
        let status = try await repo.session(s.id)?.status
        XCTAssertEqual(status, .recovered)
    }

    func testRecognizerFailureLeavesJournalAndSession() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let s = session()
        try await repo.createSession(s)
        for chunk in chunks(1) { await journals.record(chunk) }
        let engine = RecoveryEngine(repository: repo, journals: journals,
                                    recognizer: FakeSpeechRecognizer(failMakeStream: true))
        let report = await engine.recover()
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.recovered, 0)
        let status = try await repo.session(s.id)?.status
        XCTAssertEqual(status, .recording)
        let remaining = await journals.sampleCount(session: s.id, source: .mic)
        XCTAssertEqual(remaining, 1_600)
    }

    func testMeetingRecoversBothSources() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let s = session(kind: .meeting)
        try await repo.createSession(s)
        for chunk in chunks(2, source: .mic) { await journals.record(chunk) }
        for chunk in chunks(3, source: .system) { await journals.record(chunk) }
        let engine = RecoveryEngine(repository: repo, journals: journals,
                                    recognizer: FakeSpeechRecognizer(script: ["remote words"], samplesPerSegment: 1_600))
        let report = await engine.recover()
        XCTAssertEqual(report.recovered, 1)
        XCTAssertEqual(report.samplesReplayed, 8_000)
        let segments = try await repo.segments(session: s.id)
        XCTAssertTrue(segments.contains { $0.source == .mic })
        XCTAssertTrue(segments.contains { $0.source == .system })
    }

    func testInjectedCleanerReCleansRawSegments() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let s = session()
        try await repo.createSession(s)
        try await repo.appendSegment(Segment(sessionID: s.id, index: 0, startMs: 0, endMs: 100,
                                             source: .mic, rawText: "raw words", cleanupState: .pending))
        let engine = RecoveryEngine(repository: repo, journals: journals,
                                    recognizer: FakeSpeechRecognizer(),
                                    cleaner: { text in RecoveryCleaned(text: text.uppercased(), state: .cleaned) })
        let report = await engine.recover()
        XCTAssertEqual(report.segmentsCleaned, 1)
        XCTAssertEqual(report.recoveredTranscripts.first?.text, "RAW WORDS")
        let segments = try await repo.segments(session: s.id)
        XCTAssertEqual(segments.first?.cleanedText, "RAW WORDS")
        XCTAssertEqual(segments.first?.cleanupState, .cleaned)
    }

    func testRecoveryIsIdempotentWhenNothingLeft() async throws {
        let repo = InMemoryRepository()
        let s = session()
        try await repo.createSession(s)
        let engine = RecoveryEngine(repository: repo, journals: FakeJournalStore(),
                                    recognizer: FakeSpeechRecognizer())
        _ = await engine.recover()
        let second = await engine.recover()
        XCTAssertEqual(second.scanned, 0)
        XCTAssertEqual(second.recovered, 0)
    }

    func testKeepJournalsSetting() async throws {
        let repo = InMemoryRepository()
        let journals = FakeJournalStore()
        let s = session()
        try await repo.createSession(s)
        for chunk in chunks(1) { await journals.record(chunk) }
        let engine = RecoveryEngine(repository: repo, journals: journals,
                                    recognizer: FakeSpeechRecognizer(samplesPerSegment: 1_600),
                                    keepJournals: true)
        _ = await engine.recover()
        let remaining = await journals.sampleCount(session: s.id, source: .mic)
        XCTAssertEqual(remaining, 1_600)
    }
}
