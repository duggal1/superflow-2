import AVFoundation
import Foundation
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowAudioJournal

final class AudioArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func clipURL(_ session: SessionID) -> URL {
        root.appendingPathComponent("\(session.value).m4a")
    }

    private func voice(_ count: Int, offset: Int) -> [Float] {
        (0..<count).map { Float(sin(Double(offset + $0) * 0.05)) * 0.2 }
    }

    /// The archive is the owner's own recording. A finished clip has to exist on disk,
    /// be playable, and report the samples that were written; that check is what was
    /// missing while a session could end with no audio at all.
    func testFinishedClipIsWrittenAndPlayable() async throws {
        let session = SessionID(UUID().uuidString)
        let archive = AudioArchiveAdapter(directory: root)
        let writer = try await archive.makeWriter(session: session)
        var start: Int64 = 0
        for index in 0..<10 {
            let samples = voice(1_600, offset: index * 1_600)
            await writer.append(AudioChunk(samples: samples, startSample: start, source: .mic))
            start += 1_600
        }

        let clip = await writer.finish()

        XCTAssertEqual(clip?.url, clipURL(session))
        let size = (try FileManager.default.attributesOfItem(atPath: clipURL(session).path)[.size]) as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "a finished clip must not be an empty file")
        XCTAssertEqual(clip?.duration ?? 0, 1.0, accuracy: 0.05)
        XCTAssertEqual(clip?.peaks.count, 20, "one peak per 50 ms of audio")

        // A closed, finalized container is what makes History's player work.
        let file = try AVAudioFile(forReading: clipURL(session))
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertGreaterThan(file.length, 0)
    }

    func testDiscardLeavesNothingBehind() async throws {
        let session = SessionID(UUID().uuidString)
        let archive = AudioArchiveAdapter(directory: root)
        let writer = try await archive.makeWriter(session: session)
        await writer.append(AudioChunk(samples: voice(1_600, offset: 0), startSample: 0, source: .mic))

        await writer.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: clipURL(session).path))
    }

    func testSweepRemovesClipsPastRetention() async throws {
        let session = SessionID(UUID().uuidString)
        let archive = AudioArchiveAdapter(directory: root)
        let writer = try await archive.makeWriter(session: session)
        await writer.append(AudioChunk(samples: voice(1_600, offset: 0), startSample: 0, source: .mic))
        _ = await writer.finish()
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-8 * 86_400)],
            ofItemAtPath: clipURL(session).path)

        await archive.sweep(olderThanDays: 7)

        XCTAssertFalse(FileManager.default.fileExists(atPath: clipURL(session).path))
    }
}
