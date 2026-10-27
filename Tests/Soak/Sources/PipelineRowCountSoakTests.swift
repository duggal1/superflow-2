import Foundation
import SuperflowAudioJournal
import SuperflowKernel
import SuperflowPorts
import SuperflowSessionEngine
import SuperflowStorageSQLite
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline
import XCTest

/// Full-pipeline soak: capture -> journal -> streaming ASR -> text pipeline -> SQLite, driven
/// through the real `SessionEngine` over the real journal and the real SQLite repository.
///
/// The plan's release gate is that an accelerated run and a real-time run of the same audio
/// produce matching transcript row counts (and matching journaled samples). Pacing is the only
/// difference between the two runs, so any divergence is a scheduling bug in the pipeline, not a
/// property of the input.
final class PipelineRowCountSoakTests: XCTestCase {
    func testAcceleratedAndRealTimeRunsProduceMatchingTranscriptRows() async throws {
        guard let raw = ProcessInfo.processInfo.environment["SUPERFLOW_SOAK_SECONDS"],
              let seconds = Int(raw), seconds > 0 else {
            throw XCTSkip("Set SUPERFLOW_SOAK_SECONDS to run the full-pipeline soak.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowPipelineSoak-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Reserve journal capacity up front so a long soak does not fail on disk pressure.
        let available = try XCTUnwrap(try root.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage)
        let required = Int64(seconds) * Int64(sampleRate) * 2 + 64 * 1_024 * 1_024
        guard available >= required else {
            throw XCTSkip("Pipeline soak needs \(required) free bytes; only \(available) are available.")
        }

        let accelerated = try await run(seconds: seconds, realtime: false, root: root)
        XCTAssertEqual(accelerated.journaled, accelerated.samples,
                       "the journal lost samples in the accelerated run")
        XCTAssertEqual(accelerated.rows, seconds,
                       "expected one committed transcript row per second of audio")
        XCTAssertTrue(accelerated.resolved, "every row must resolve out of the pending cleanup state")
        XCTAssertFalse(accelerated.text.isEmpty)

        guard ProcessInfo.processInfo.environment["SUPERFLOW_SOAK_REALTIME"] == "1" else {
            throw XCTSkip("Set SUPERFLOW_SOAK_REALTIME=1 to compare against the real-time run.")
        }
        let realtime = try await run(seconds: seconds, realtime: true, root: root)

        XCTAssertEqual(realtime.journaled, realtime.samples,
                       "the journal lost samples in the real-time run")
        XCTAssertEqual(realtime.rows, accelerated.rows,
                       "accelerated and real-time runs produced different transcript row counts")
        XCTAssertEqual(realtime.journaled, accelerated.journaled,
                       "accelerated and real-time runs journaled different sample counts")
        XCTAssertEqual(realtime.text, accelerated.text,
                       "accelerated and real-time runs produced different transcripts")
    }

    private struct RunResult {
        var samples: Int64
        var journaled: Int64
        var rows: Int
        var text: String
        var resolved: Bool
    }

    private func run(seconds: Int, realtime: Bool, root: URL) async throws -> RunResult {
        let tag = realtime ? "realtime" : "accelerated"
        let journal = FileJournalStore(
            root: root.appendingPathComponent("journals-\(tag)", isDirectory: true),
            keepAfterClose: true, minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let store = try SQLiteStore(
            path: root.appendingPathComponent("history-\(tag).sqlite").path)

        var settings = AppSettings.default
        settings.commandsEnabled = false
        // Cleanup stays on so every row must resolve out of `.pending`, exercising the
        // background coordinator's queue under both paces.
        settings.cleanupEnabled = true
        settings.harperEnabled = false
        settings.keepJournals = true
        let pipeline = TextPipelineBuilder.make(
            settings: settings,
            dependencies: TextPipelineDependencies(
                cleaner: CleanupService(cleaner: FakeTextCleaner(.identity))))

        let totalSamples = Int64(seconds) * Int64(sampleRate)
        let recognizer = FakeSpeechRecognizer(script: ["soak segment words"],
                                              samplesPerSegment: sampleRate)
        let audio = PacedMicrophoneSource(totalSamples: totalSamples, realtime: realtime)
        let engine = SessionEngine(
            audio: audio, recognizer: recognizer, pipeline: pipeline, repository: store,
            journals: journal, inserter: RecordingInserter(), settings: settings)

        let id = try await engine.start()
        // Let capture deliver every sample (in real time, when pacing is on) before stopping, so
        // the run length is the audio length and not the test harness's speed.
        await audio.waitUntilFinished()
        let outcome = await engine.stop()
        let rows = try await store.segments(session: id)
        let journaled = await journal.sampleCount(session: id, source: .mic)
        return RunResult(samples: totalSamples, journaled: journaled, rows: rows.count,
                         text: outcome?.text ?? "",
                         resolved: rows.allSatisfy { $0.cleanupState != .pending })
    }
}

/// Microphone source that emits contiguous chunks and, in real-time mode, sleeps for each chunk's
/// duration. The generator applies backpressure by retrying on a dropped yield, so no sample is
/// ever silently discarded, in either mode.
private final class PacedMicrophoneSource: AudioSource, @unchecked Sendable {
    let kind: AudioSourceKind = .mic
    private let chunks: [AudioChunk]
    private let realtime: Bool
    private let lock = NSLock()
    private var stopped = false
    private var finished = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    init(totalSamples: Int64, chunkSamples: Int = 1_600, realtime: Bool) {
        self.realtime = realtime
        var built: [AudioChunk] = []
        var cursor: Int64 = 0
        while cursor < totalSamples {
            let count = Int(min(Int64(chunkSamples), totalSamples - cursor))
            built.append(AudioChunk(samples: [Float](repeating: 0.2, count: count),
                                    startSample: cursor, source: .mic))
            cursor += Int64(count)
        }
        chunks = built
    }

    func start() async throws -> AudioStreams {
        let (samples, samplesContinuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingOldest(64))
        let (events, eventsContinuation) = AsyncStream<AudioEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(8))
        Task { [weak self] in
            guard let self else {
                samplesContinuation.finish()
                eventsContinuation.finish()
                return
            }
            for chunk in chunks {
                guard !isStopped else { break }
                guard await yield(chunk, to: samplesContinuation) else { break }
                if realtime {
                    try? await Task.sleep(for: .seconds(Double(chunk.samples.count) / Double(sampleRate)))
                }
            }
            samplesContinuation.finish()
            eventsContinuation.yield(.stopped)
            eventsContinuation.finish()
            markFinished()
        }
        return AudioStreams(samples: samples, events: events)
    }

    func stop() async {
        lock.withLock { stopped = true }
        markFinished()
    }

    /// Resolves once the generator has delivered (or been stopped before delivering) every chunk.
    func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            let alreadyDone = lock.withLock { () -> Bool in
                if finished { return true }
                finishWaiters.append(continuation)
                return false
            }
            if alreadyDone { continuation.resume() }
        }
    }

    private func markFinished() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            finished = true
            let pending = finishWaiters
            finishWaiters = []
            return pending
        }
        for waiter in waiters { waiter.resume() }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func yield(_ chunk: AudioChunk,
                       to continuation: AsyncStream<AudioChunk>.Continuation) async -> Bool {
        while !isStopped {
            switch continuation.yield(chunk) {
            case .enqueued: return true
            case .terminated: return false
            case .dropped: try? await Task.sleep(for: .milliseconds(2))
            @unknown default: return false
            }
        }
        return false
    }
}
