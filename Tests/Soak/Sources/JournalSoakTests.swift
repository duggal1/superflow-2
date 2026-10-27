import Foundation
import SuperflowAudioJournal
import SuperflowKernel
import Darwin
import XCTest

final class JournalSoakTests: XCTestCase {
    func testConfiguredDurationIsFullyJournaledAndReplayable() async throws {
        guard let raw = ProcessInfo.processInfo.environment["SUPERFLOW_SOAK_SECONDS"],
              let seconds = Int(raw), seconds > 0 else {
            throw XCTSkip("Set SUPERFLOW_SOAK_SECONDS to run the journal soak.")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowJournalSoak-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let available = try XCTUnwrap(try root.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage)
        let required = Int64(seconds) * Int64(sampleRate) * 2 + 64 * 1_024 * 1_024
        guard available >= required else {
            throw XCTSkip("Journal soak needs \(required) free bytes; only \(available) are available.")
        }

        let store = FileJournalStore(root: root, keepAfterClose: true,
                                     minimumStartFreeBytes: 0, lowDiskWarningBytes: 0)
        let session = SessionID()
        let writer = try await store.openWriter(session: session, source: .mic)
        let samplesPerChunk = sampleRate
        let chunk = [Float](repeating: 0.125, count: samplesPerChunk)
        let totalSamples = Int64(seconds) * Int64(sampleRate)

        let warmupSamples = min(totalSamples, Int64(sampleRate) * 10)
        var start: Int64 = 0
        while start < warmupSamples {
            let count = Int(min(Int64(samplesPerChunk), warmupSamples - start))
            await writer.append(AudioChunk(samples: Array(chunk.prefix(count)), startSample: start, source: .mic))
            start += Int64(count)
        }
        let warmupRSS = try XCTUnwrap(residentMemoryBytes())
        while start < totalSamples {
            let count = Int(min(Int64(samplesPerChunk), totalSamples - start))
            await writer.append(AudioChunk(samples: Array(chunk.prefix(count)), startSample: start, source: .mic))
            start += Int64(count)
            if ProcessInfo.processInfo.environment["SUPERFLOW_SOAK_REALTIME"] == "1" {
                try await Task.sleep(for: .seconds(Double(count) / Double(sampleRate)))
            }
        }
        let summary = await writer.close()
        XCTAssertFalse(summary.degraded)
        XCTAssertEqual(summary.samples, totalSamples)
        let storedSamples = await store.sampleCount(session: session, source: .mic)
        XCTAssertEqual(storedSamples, totalSamples)

        var replayed: Int64 = 0
        var expectedStart: Int64 = 0
        for await replayChunk in await store.replay(session: session, source: .mic, fromSample: 0) {
            XCTAssertEqual(replayChunk.startSample, expectedStart)
            XCTAssertEqual(replayChunk.source, .mic)
            expectedStart = replayChunk.endSample
            replayed += Int64(replayChunk.samples.count)
        }
        XCTAssertEqual(replayed, totalSamples)
        let finalRSS = try XCTUnwrap(residentMemoryBytes())
        let growth = finalRSS > warmupRSS ? finalRSS - warmupRSS : 0
        XCTAssertLessThanOrEqual(growth, 50 * 1_024 * 1_024,
                                 "Resident memory grew by more than the plan's 50 MB soak budget.")
    }

    private func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
}
