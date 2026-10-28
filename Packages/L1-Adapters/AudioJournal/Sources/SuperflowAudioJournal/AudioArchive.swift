import AVFoundation
import Foundation
import SuperflowKernel
import SuperflowPorts

/// Writes the exact buffers the recognizer heard, as 16 kHz mono AAC in `.m4a`.
/// Peaks are computed while writing (20 per second, one byte each), so the player
/// never decodes audio just to draw a waveform.
///
/// The render/capture path only copies and yields; encoding and disk I/O happen
/// on a detached utility task. No AVFoundation object crosses a concurrency
/// boundary: the format and file are created inside the task.
public final class M4AArchiveWriter: AudioArchiveWriter, @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    private static let samplesPerPeak = 800          // 50 ms
    private static let floorDB: Float = -54
    private static let ceilDB: Float = -6

    private let input: AsyncStream<[Float]>.Continuation
    private let work: Task<ArchivedAudio?, Never>
    private let url: URL

    public init(url: URL) {
        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        input = continuation
        self.url = url
        work = Task.detached(priority: .utility) {
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: Self.sampleRate,
                                             channels: 1, interleaved: false),
                  let file = try? AVAudioFile(forWriting: url, settings: [
                      AVFormatIDKey: kAudioFormatMPEG4AAC,
                      AVSampleRateKey: Self.sampleRate,
                      AVNumberOfChannelsKey: 1,
                      AVEncoderBitRateKey: 32_000,
                  ], commonFormat: .pcmFormatFloat32, interleaved: false)
            else { return nil }

            var peaks: [UInt8] = []
            var frames = 0
            var filled = 0
            var peak: Float = 0

            for await chunk in stream {
                guard !chunk.isEmpty,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                    frameCapacity: AVAudioFrameCount(chunk.count))
                else { continue }
                buffer.frameLength = AVAudioFrameCount(chunk.count)
                chunk.withUnsafeBufferPointer { source in
                    guard let base = source.baseAddress else { return }
                    buffer.floatChannelData?[0].update(from: base, count: chunk.count)
                }
                do { try file.write(from: buffer) } catch { return nil }
                frames += chunk.count
                for sample in chunk {
                    peak = max(peak, abs(sample))
                    filled += 1
                    if filled == Self.samplesPerPeak {
                        peaks.append(Self.level(peak))
                        peak = 0
                        filled = 0
                    }
                }
            }
            // Finalize the container before the value escapes, so a finished clip is
            // always playable instead of depending on when the file deinitialises.
            file.close()
            if filled > 0 { peaks.append(Self.level(peak)) }
            guard frames > 0 else { return nil }
            return ArchivedAudio(url: url,
                                 duration: Double(frames) / Self.sampleRate,
                                 peaks: peaks)
        }
    }

    public func append(_ chunk: AudioChunk) async {
        input.yield(chunk.samples)
    }

    public func finish() async -> ArchivedAudio? {
        input.finish()
        return await work.value
    }

    public func discard() async {
        input.finish()
        _ = await work.value
        // Remove the path even when nothing usable was written: the file was
        // already opened on disk.
        try? FileManager.default.removeItem(at: url)
    }

    private static func level(_ peak: Float) -> UInt8 {
        guard peak > 0 else { return 0 }
        let db = 20 * log10(peak)
        let normalized = (db - floorDB) / (ceilDB - floorDB)
        return UInt8((min(max(normalized, 0), 1) * 255).rounded())
    }
}

/// Files live in Application Support, excluded from backup, and never leave the Mac.
public struct AudioArchiveAdapter: AudioArchiveStore {
    private let directory: URL
    public init(directory: URL = AudioArchiveLocation.directory()) {
        self.directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        try? url.setResourceValues(values)
    }

    public func makeWriter(session: SessionID) async throws -> any AudioArchiveWriter {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return M4AArchiveWriter(url: directory.appendingPathComponent("\(session.value).m4a"))
    }

    public func delete(session: SessionID) async {
        try? FileManager.default.removeItem(at: url(for: session))
    }

    /// A nil retention keeps every clip. Anything older is removed and its row
    /// metadata is cleared by the caller's sweep.
    public func sweep(olderThanDays days: Int?) async {
        guard let days, days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "m4a" {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func url(for session: SessionID) -> URL {
        directory.appendingPathComponent("\(session.value).m4a")
    }
}
