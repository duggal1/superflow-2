import Foundation
import SuperflowAudioJournal
import SuperflowKernel
import SuperflowMeetingEngine
import SuperflowTestKit
import SuperflowTextPipeline
import XCTest

/// Real-writer coverage for the meeting system lane. Unlike the engine unit tests, which use
/// `FakeJournalStore`, this drives the actual `FileJournalStore` so the on-disk manifest and
/// sample positions are exercised end to end. It pins the offset contract: the system lane must
/// be journaled on the shared meeting clock (starting at the source's offset), never at sample 0,
/// or the lane is silently dropped and recovery cannot replay it.
final class MeetingJournalOffsetTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowMeetingJournal-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSystemLaneIsJournaledOnTheSharedClockAndReplayable() async throws {
        let store = FileJournalStore(root: root, keepAfterClose: true,
                                     minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let clock = SteppingClock(stepNs: 250_000_000)
        var settings = AppSettings.default
        settings.keepJournals = true
        settings.cleanupEnabled = false
        settings.harperEnabled = false
        let pipeline = TextPipelineBuilder.make(settings: settings,
                                                dependencies: TextPipelineDependencies())
        let recognizer = FakeSpeechRecognizer(
            script: ["mic words"],
            scriptsBySource: [.mic: ["mic words"], .system: ["remote words"]],
            samplesPerSegment: 80_000)
        let engine = MeetingEngine(
            mic: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .mic),
            system: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 160_000), kind: .system),
            recognizer: recognizer, pipeline: pipeline,
            repository: InMemoryRepository(), journals: store, settings: settings, clock: clock)

        let session = try await engine.start()
        _ = await engine.stop()

        // The microphone lane is on the shared clock from 0 and keeps every sample.
        let micEnd = await store.sampleCount(session: session, source: .mic)
        XCTAssertEqual(micEnd, 160_000, "microphone lane did not keep the full sample count")

        // 250 ms of monotonic drift before the system source started == 4_000 samples at 16 kHz.
        let systemEnd = await store.sampleCount(session: session, source: .system)
        XCTAssertEqual(systemEnd, 4_000 + 160_000,
                       "system lane was not journaled at its shared-clock offset")

        // Replay returns the system lane at the offset, not at 0: this is exactly what recovery
        // relies on to resume past the committed segments.
        var firstStart: Int64?
        var replayed: Int64 = 0
        for await chunk in await store.replay(session: session, source: .system, fromSample: 0) {
            if firstStart == nil { firstStart = chunk.startSample }
            XCTAssertEqual(chunk.source, .system)
            replayed += Int64(chunk.samples.count)
        }
        XCTAssertEqual(firstStart, 4_000, "replayed system lane began at the wrong sample")
        XCTAssertEqual(replayed, 160_000, "replayed system lane lost samples")

        // Replaying past the committed portion still yields the trailing audio rather than
        // being skipped, which is the recovery failure mode the offset bug caused.
        var tail: Int64 = 0
        for await chunk in await store.replay(session: session, source: .system, fromSample: 120_000) {
            tail += Int64(chunk.samples.count)
        }
        XCTAssertEqual(tail, 160_000 - (120_000 - 4_000),
                       "replay from a committed position did not return the trailing samples")
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
