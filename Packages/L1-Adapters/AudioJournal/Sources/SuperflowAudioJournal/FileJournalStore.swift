import Foundation
import SuperflowKernel
import SuperflowPorts

struct JournalSegment: Codable, Sendable, Equatable {
    let file: String
    let index: Int
    let startSample: Int64
}

enum JournalManifest {
    static func fileName(for source: AudioSourceKind) -> String { "\(source.rawValue)-manifest.jsonl" }

    static func read(directory: URL, source: AudioSourceKind) -> [JournalSegment] {
        let url = directory.appendingPathComponent(fileName(for: source))
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let prefix = "\(source.rawValue)-"
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let entry = try? JSONDecoder().decode(JournalSegment.self, from: data),
                      entry.file.hasPrefix(prefix), entry.file.hasSuffix(".pcm"),
                      URL(fileURLWithPath: entry.file).lastPathComponent == entry.file,
                      entry.index >= 0, entry.startSample >= 0 else { return nil }
                return entry
            }
            .sorted { $0.index < $1.index }
    }
}

/// Stores one session/source lane as append-only manifest entries and 60-second Int16 PCM files.
public actor FileJournalStore: JournalStore {
    public static let segmentDurationSamples: Int64 = Int64(sampleRate) * 60
    public static let minimumStartFreeBytes: Int64 = 3 * 1_024 * 1_024 * 1_024
    public static let lowDiskWarningBytes: Int64 = 1 * 1_024 * 1_024 * 1_024

    private let root: URL
    private let fileManager: FileManager
    private let keepAfterClose: Bool
    private let minimumStartFreeBytes: Int64
    private let lowDiskWarningBytes: Int64

    public init(root: URL? = nil, keepAfterClose: Bool = false,
                minimumStartFreeBytes: Int64 = 3 * 1_024 * 1_024 * 1_024,
                lowDiskWarningBytes: Int64 = 1 * 1_024 * 1_024 * 1_024,
                fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.keepAfterClose = keepAfterClose
        self.minimumStartFreeBytes = max(0, minimumStartFreeBytes)
        self.lowDiskWarningBytes = max(0, lowDiskWarningBytes)
        self.root = root ?? Self.defaultRoot(fileManager: fileManager)
    }

    public static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Superflow/Journals", isDirectory: true)
    }

    public func openWriter(session: SessionID, source: AudioSourceKind,
                           startingSample: Int64) async throws -> any AudioJournalWriter {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let available = availableBytes(at: root)
        guard available >= minimumStartFreeBytes else { throw SuperflowError.diskFull }
        let directory = sessionDirectory(session)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent("\(source.rawValue).pcm")
        let legacySamples = fileSize(legacyURL) / Int64(MemoryLayout<Float>.size)
        // The lane begins at the caller's shared-clock position; a resumed lane keeps whichever
        // position is further along so an offset never rewinds the manifest.
        let start = max(legacySamples, max(0, startingSample))
        return try PCMJournalWriter(directory: directory, source: source,
                                    startingSamples: start,
                                    lowDiskWarningBytes: lowDiskWarningBytes)
    }

    public func replay(session: SessionID, source: AudioSourceKind,
                       fromSample: Int64) async -> AsyncStream<AudioChunk> {
        let directory = sessionDirectory(session)
        let legacyURL = directory.appendingPathComponent("\(source.rawValue).pcm")
        let legacySamples = fileSize(legacyURL) / Int64(MemoryLayout<Float>.size)
        let segments = JournalManifest.read(directory: directory, source: source)
            .compactMap { entry -> (JournalSegment, URL, Int64)? in
                let url = directory.appendingPathComponent(entry.file)
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                return (entry, url, fileSize(url) / Int64(MemoryLayout<Int16>.size))
            }

        return AsyncStream(bufferingPolicy: .bufferingOldest(32)) { continuation in
            let task = Task.detached(priority: .utility) {
                if legacySamples > 0 {
                    let complete = await Self.replayLegacy(url: legacyURL, source: source, samples: legacySamples,
                                                           fromSample: max(0, fromSample), continuation: continuation)
                    if !complete { continuation.finish(); return }
                }
                for (entry, url, count) in segments {
                    let segmentEnd = entry.startSample + count
                    guard segmentEnd > fromSample else { continue }
                    let skip = max(0, fromSample - entry.startSample)
                    let complete = await Self.replayInt16(url: url, source: source,
                                                          startSample: entry.startSample + skip,
                                                          skipSamples: skip, sampleCount: count - skip,
                                                          continuation: continuation)
                    if !complete { continuation.finish(); return }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func sessionsWithJournals() async -> [SessionID] {
        let urls = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { SessionID($0.lastPathComponent) }
            .sorted { $0.value < $1.value }
    }

    /// The lane's end position on the shared clock, not a raw sample total. Recovery compares it
    /// against committed segment timestamps, so a lane starting at an offset must report
    /// `offset + journaled` rather than only the journaled count.
    public func sampleCount(session: SessionID, source: AudioSourceKind) async -> Int64 {
        let directory = sessionDirectory(session)
        let legacyURL = directory.appendingPathComponent("\(source.rawValue).pcm")
        var end = fileSize(legacyURL) / Int64(MemoryLayout<Float>.size)
        for entry in JournalManifest.read(directory: directory, source: source) {
            let count = fileSize(directory.appendingPathComponent(entry.file)) / Int64(MemoryLayout<Int16>.size)
            end = max(end, entry.startSample + count)
        }
        return end
    }

    public func delete(session: SessionID) async {
        guard !keepAfterClose else { return }
        try? fileManager.removeItem(at: sessionDirectory(session))
    }

    public func freeBytes() async -> Int64 { availableBytes(at: root) }

    private func sessionDirectory(_ session: SessionID) -> URL {
        root.appendingPathComponent(session.value, isDirectory: true)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func availableBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private static func replayLegacy(url: URL, source: AudioSourceKind, samples: Int64, fromSample: Int64,
                                     continuation: AsyncStream<AudioChunk>.Continuation) async -> Bool {
        guard fromSample < samples, let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(fromSample) * 4)) != nil else { return true }
        return await readFloatChunks(handle: handle, source: source, cursor: fromSample,
                                     sampleCount: samples - fromSample, continuation: continuation)
    }

    private static func replayInt16(url: URL, source: AudioSourceKind, startSample: Int64,
                                    skipSamples: Int64, sampleCount: Int64,
                                    continuation: AsyncStream<AudioChunk>.Continuation) async -> Bool {
        guard sampleCount > 0, let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(skipSamples) * 2)) != nil else { return true }
        var cursor = startSample
        var remaining = sampleCount
        while remaining > 0, !Task.isCancelled {
            let count = Int(min(Int64(sampleRate), remaining))
            guard let data = try? handle.read(upToCount: count * 2), !data.isEmpty else { break }
            let samples = data.withUnsafeBytes { raw -> [Float] in
                let count = raw.count / MemoryLayout<Int16>.size
                return (0..<count).map { index in
                    let value = raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self).littleEndian
                    return Float(value) / Float(Int16.max)
                }
            }
            guard await yield(AudioChunk(samples: samples, startSample: cursor, source: source), to: continuation) else { return false }
            cursor += Int64(samples.count)
            remaining -= Int64(samples.count)
        }
        return !Task.isCancelled
    }

    private static func readFloatChunks(handle: FileHandle, source: AudioSourceKind, cursor start: Int64,
                                        sampleCount: Int64,
                                        continuation: AsyncStream<AudioChunk>.Continuation) async -> Bool {
        var cursor = start
        var remaining = sampleCount
        while remaining > 0, !Task.isCancelled {
            let count = Int(min(Int64(sampleRate), remaining))
            guard let data = try? handle.read(upToCount: count * 4), !data.isEmpty else { break }
            let samples = data.withUnsafeBytes { raw -> [Float] in
                let count = raw.count / MemoryLayout<Float>.size
                return (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
            }
            guard await yield(AudioChunk(samples: samples, startSample: cursor, source: source), to: continuation) else { return false }
            cursor += Int64(samples.count)
            remaining -= Int64(samples.count)
        }
        return !Task.isCancelled
    }

    private static func yield(_ chunk: AudioChunk,
                              to continuation: AsyncStream<AudioChunk>.Continuation) async -> Bool {
        while !Task.isCancelled {
            switch continuation.yield(chunk) {
            case .enqueued: return true
            case .terminated: return false
            case .dropped:
                try? await Task.sleep(for: .milliseconds(5))
            @unknown default: return false
            }
        }
        return false
    }
}
