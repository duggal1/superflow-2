import Foundation
import SuperflowKernel
import SuperflowPorts

actor PCMJournalWriter: AudioJournalWriter {
    private static let syncEverySamples: Int64 = Int64(sampleRate) * 5

    private let directory: URL
    private let source: AudioSourceKind
    private let manifestURL: URL
    private let lowDiskWarningBytes: Int64
    private let fileManager = FileManager.default
    private var manifestHandle: FileHandle
    private var entries: [JournalSegment]
    private var totalSamples: Int64
    private var nextIndex: Int
    private var activeEntry: JournalSegment?
    private var activeHandle: FileHandle?
    private var activeSamples: Int64 = 0
    private var pendingSyncSamples: Int64 = 0
    private var degraded = false
    private var closed = false

    init(directory: URL, source: AudioSourceKind, startingSamples: Int64,
         lowDiskWarningBytes: Int64) throws {
        self.directory = directory
        self.source = source
        self.manifestURL = directory.appendingPathComponent(JournalManifest.fileName(for: source))
        self.lowDiskWarningBytes = lowDiskWarningBytes
        try Self.repairTrailingManifestLine(at: manifestURL)
        entries = JournalManifest.read(directory: directory, source: source)
        totalSamples = max(0, startingSamples)
        nextIndex = (entries.map(\.index).max() ?? -1) + 1

        var lastEntry: JournalSegment?
        var lastCount: Int64 = 0
        for entry in entries {
            let url = directory.appendingPathComponent(entry.file)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let bytes = Self.fileSize(url)
            let validBytes = bytes - bytes % 2
            if validBytes != bytes {
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: UInt64(validBytes))
                try handle.close()
            }
            let count = validBytes / 2
            totalSamples = max(totalSamples, entry.startSample + count)
            lastEntry = entry
            lastCount = count
        }

        if let lastEntry, lastCount < FileJournalStore.segmentDurationSamples {
            let url = directory.appendingPathComponent(lastEntry.file)
            if fileManager.fileExists(atPath: url.path) {
                activeHandle = try FileHandle(forUpdating: url)
                try activeHandle?.seekToEnd()
                activeEntry = lastEntry
                activeSamples = lastCount
            }
        }

        if !fileManager.fileExists(atPath: manifestURL.path) {
            fileManager.createFile(atPath: manifestURL.path, contents: nil)
        }
        manifestHandle = try FileHandle(forUpdating: manifestURL)
        try manifestHandle.seekToEnd()
    }

    var isDegraded: Bool { degraded }

    func append(_ chunk: AudioChunk) async {
        guard !closed, !degraded, !chunk.samples.isEmpty else { return }
        guard chunk.source == source, chunk.startSample == totalSamples else {
            await failJournal()
            return
        }

        do {
            var offset = 0
            while offset < chunk.samples.count {
                if activeHandle == nil { try openNextSegment() }
                let availableInSegment = FileJournalStore.segmentDurationSamples - activeSamples
                let count = min(chunk.samples.count - offset, Int(availableInSegment))
                guard count > 0, let handle = activeHandle else {
                    await failJournal()
                    return
                }
                let data = Self.encode(chunk.samples[offset..<(offset + count)])
                try handle.write(contentsOf: data)
                offset += count
                activeSamples += Int64(count)
                totalSamples += Int64(count)
                pendingSyncSamples += Int64(count)

                if activeSamples == FileJournalStore.segmentDurationSamples {
                    try synchronize()
                    try handle.close()
                    activeHandle = nil
                    activeEntry = nil
                    activeSamples = 0
                }
                if pendingSyncSamples >= Self.syncEverySamples {
                    try synchronize()
                    pendingSyncSamples = 0
                    if availableBytes() < lowDiskWarningBytes {
                        await failJournal()
                        return
                    }
                }
            }
        } catch {
            await failJournal()
        }
    }

    func close() async -> JournalSummary {
        guard !closed else { return JournalSummary(samples: totalSamples, degraded: degraded) }
        closed = true
        do { try synchronize() } catch { degraded = true }
        try? activeHandle?.close()
        try? manifestHandle.close()
        activeHandle = nil
        return JournalSummary(samples: totalSamples, degraded: degraded)
    }

    private func openNextSegment() throws {
        let fileName = String(format: "%@-%06d.pcm", source.rawValue, nextIndex)
        let entry = JournalSegment(file: fileName, index: nextIndex, startSample: totalSamples)
        let encoded = try JSONEncoder().encode(entry)
        var line = encoded
        line.append(0x0A)
        try manifestHandle.write(contentsOf: line)
        try manifestHandle.synchronize()

        let url = directory.appendingPathComponent(fileName)
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteFileExists)
        }
        activeHandle = try FileHandle(forUpdating: url)
        activeEntry = entry
        activeSamples = 0
        entries.append(entry)
        nextIndex += 1
    }

    private func synchronize() throws {
        try activeHandle?.synchronize()
        try manifestHandle.synchronize()
    }

    private func availableBytes() -> Int64 {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func failJournal() async {
        degraded = true
        try? activeHandle?.synchronize()
        try? manifestHandle.synchronize()
        try? activeHandle?.close()
        activeHandle = nil
    }

    private static func encode(_ samples: ArraySlice<Float>) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let finite = sample.isFinite ? sample : 0
            let bounded = min(1, max(-1, finite))
            var pcm = Int16((bounded * Float(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: &pcm) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func repairTrailingManifestLine(at url: URL) throws {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              data.last != 0x0A else { return }
        let validLength = data.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(validLength))
        try handle.synchronize()
        try handle.close()
    }
}
