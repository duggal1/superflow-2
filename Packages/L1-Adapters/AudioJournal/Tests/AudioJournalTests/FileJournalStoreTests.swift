import Foundation
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowAudioJournal

final class FileJournalStoreTests: XCTestCase {
    private var root: URL!
    private var store: FileJournalStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = FileJournalStore(root: root, minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAppendCloseAndCount() async throws {
        let session = SessionID("s1")
        let writer = try await store.openWriter(session: session, source: .mic)
        await writer.append(AudioChunk(samples: [Float](repeating: 0.25, count: 1_600),
                                       startSample: 0, source: .mic))
        await writer.append(AudioChunk(samples: [Float](repeating: -0.5, count: 400),
                                       startSample: 1_600, source: .mic))
        let summary = await writer.close()
        XCTAssertEqual(summary.samples, 2_000)
        XCTAssertFalse(summary.degraded)
        let count = await store.sampleCount(session: session, source: .mic)
        XCTAssertEqual(count, 2_000)
    }

    func testReplayFromOffsetKeepsTimestamps() async throws {
        let session = SessionID("s2")
        let writer = try await store.openWriter(session: session, source: .system)
        let first = (0..<1_600).map { Float($0) / 1_600 }
        let second = (0..<1_600).map { Float($0) / 3_200 }
        await writer.append(AudioChunk(samples: first, startSample: 0, source: .system))
        await writer.append(AudioChunk(samples: second, startSample: 1_600, source: .system))
        _ = await writer.close()

        var chunks: [AudioChunk] = []
        for await chunk in await store.replay(session: session, source: .system, fromSample: 1_600) {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].startSample, 1_600)
        XCTAssertEqual(chunks[0].samples.count, 1_600)
        XCTAssertEqual(chunks[0].samples[0], 0, accuracy: 0.0001)
    }

    func testReplayMissingJournalFinishesEmpty() async throws {
        var count = 0
        for await _ in await store.replay(session: SessionID("missing"), source: .mic, fromSample: 0) {
            count += 1
        }
        XCTAssertEqual(count, 0)
    }

    func testSessionsWithJournalsAndDelete() async throws {
        let a = SessionID("a")
        let b = SessionID("b")
        let writerA = try await store.openWriter(session: a, source: .mic)
        _ = await writerA.close()
        let writerB = try await store.openWriter(session: b, source: .system)
        _ = await writerB.close()
        let sessions = await store.sessionsWithJournals()
        XCTAssertEqual(Set(sessions), Set([a, b]))

        await store.delete(session: a)
        let after = await store.sessionsWithJournals()
        XCTAssertEqual(after, [b])
    }

    func testTruncatedFileRoundsDown() async throws {
        let session = SessionID("truncated")
        let directory = root.appendingPathComponent(session.value, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mic.pcm")
        try Data(count: 10).write(to: url)
        let count = await store.sampleCount(session: session, source: .mic)
        XCTAssertEqual(count, 2)
        var samples = 0
        for await chunk in await store.replay(session: session, source: .mic, fromSample: 0) {
            samples += chunk.samples.count
        }
        XCTAssertEqual(samples, 2)
    }

    func testFreeBytesReportsAVolume() async throws {
        let bytes = await store.freeBytes()
        XCTAssertGreaterThan(bytes, 0)
    }

    func testJournalWritesInt16AndReplaysFloatSamples() async throws {
        let session = SessionID("int16")
        let writer = try await store.openWriter(session: session, source: .mic)
        let input: [Float] = [1, -1, 0.5, -0.5]
        await writer.append(AudioChunk(samples: input, startSample: 0, source: .mic))
        let result = await writer.close()

        XCTAssertEqual(result.samples, 4)
        XCTAssertFalse(result.degraded)
        let directory = root.appendingPathComponent(session.value, isDirectory: true)
        let pcm = directory.appendingPathComponent("mic-000000.pcm")
        XCTAssertEqual(try Data(contentsOf: pcm).count, 8)

        var replayed: [Float] = []
        for await chunk in await store.replay(session: session, source: .mic, fromSample: 0) {
            replayed.append(contentsOf: chunk.samples)
        }
        XCTAssertEqual(replayed.count, 4)
        XCTAssertEqual(replayed[0], 1, accuracy: 0.001)
        XCTAssertEqual(replayed[1], -1, accuracy: 0.001)
        XCTAssertEqual(replayed[2], 0.5, accuracy: 0.001)
        XCTAssertEqual(replayed[3], -0.5, accuracy: 0.001)
    }

    func testJournalRotatesAtSixtySecondsAndKeepsSampleOffsets() async throws {
        let session = SessionID("rotation")
        let writer = try await store.openWriter(session: session, source: .system)
        let firstCount = Int(FileJournalStore.segmentDurationSamples)
        let samples = [Float](repeating: 0.25, count: firstCount + 20)
        await writer.append(AudioChunk(samples: samples, startSample: 0, source: .system))
        _ = await writer.close()

        let directory = root.appendingPathComponent(session.value, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("system-000000.pcm").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("system-000001.pcm").path))
        let writtenCount = await store.sampleCount(session: session, source: .system)
        XCTAssertEqual(writtenCount, Int64(samples.count))

        var count: Int64 = 0
        var firstStart: Int64?
        for await chunk in await store.replay(session: session, source: .system, fromSample: Int64(firstCount - 5)) {
            if firstStart == nil { firstStart = chunk.startSample }
            count += Int64(chunk.samples.count)
        }
        XCTAssertEqual(count, 25)
        XCTAssertEqual(firstStart, Int64(firstCount - 5))
    }

    func testJournalRefusesToStartBelowConfiguredFreeSpace() async throws {
        let constrainedStore = FileJournalStore(root: root.appendingPathComponent("constrained"),
                                                minimumStartFreeBytes: .max,
                                                lowDiskWarningBytes: 0)
        do {
            _ = try await constrainedStore.openWriter(session: SessionID("no-space"), source: .mic)
            XCTFail("Expected a disk-full error")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .diskFull)
        }
    }

    func testReopeningJournalTruncatesTornManifestLine() async throws {
        let session = SessionID("torn-manifest")
        let first = try await store.openWriter(session: session, source: .mic)
        await first.append(AudioChunk(samples: [0.25, 0.5], startSample: 0, source: .mic))
        _ = await first.close()

        let manifest = root.appendingPathComponent(session.value, isDirectory: true)
            .appendingPathComponent("mic-manifest.jsonl")
        let handle = try FileHandle(forWritingTo: manifest)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"file\":\"mic-000001.pcm\"".utf8))
        try handle.close()

        let resumed = try await store.openWriter(session: session, source: .mic)
        await resumed.append(AudioChunk(samples: [0.75], startSample: 2, source: .mic))
        _ = await resumed.close()

        let count = await store.sampleCount(session: session, source: .mic)
        XCTAssertEqual(count, 3)
        var replayed: [Float] = []
        for await chunk in await store.replay(session: session, source: .mic, fromSample: 0) {
            replayed.append(contentsOf: chunk.samples)
        }
        XCTAssertEqual(replayed.count, 3)
        XCTAssertEqual(replayed[2], 0.75, accuracy: 0.001)
    }

    func testReopeningWriterAppendsInsteadOfTruncating() async throws {
        let session = SessionID("resume")
        let first = try await store.openWriter(session: session, source: .mic)
        await first.append(AudioChunk(samples: [Float](repeating: 1, count: 100), startSample: 0, source: .mic))
        _ = await first.close()

        let second = try await store.openWriter(session: session, source: .mic)
        await second.append(AudioChunk(samples: [Float](repeating: 2, count: 50), startSample: 100, source: .mic))
        let summary = await second.close()
        XCTAssertEqual(summary.samples, 150)
    }
}
