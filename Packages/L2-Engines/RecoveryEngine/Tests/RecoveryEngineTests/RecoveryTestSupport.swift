import Foundation
import SuperflowKernel
import SuperflowPorts
@testable import SuperflowRecoveryEngine

/// Real, ephemeral, file-backed journal used by the aggressive recovery tests. No storage logic is
/// mocked: every sample goes through FileHandle into a temp directory that is deleted in tearDown.
/// Framing is [Int64 startSample][UInt32 sampleCount][Float32 samples...] per record, so a torn tail
/// is detectable and replay always stops at the last complete record.
actor FileBackedJournalStore: JournalStore {
    private let root: URL
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func file(_ session: SessionID, _ source: AudioSourceKind) -> URL {
        root.appendingPathComponent("\(session.value)-\(source.rawValue).journal")
    }

    func openWriter(session: SessionID, source: AudioSourceKind,
                    startingSample: Int64) async throws -> any AudioJournalWriter {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return FileBackedJournalWriter(store: self, url: file(session, source), source: source)
    }

    func replay(session: SessionID, source: AudioSourceKind, fromSample: Int64) async -> AsyncStream<AudioChunk> {
        let records = Self.records(at: file(session, source))
        let kind = source
        return AsyncStream { continuation in
            for record in records where record.end > fromSample {
                let skip = max(0, fromSample - record.start)
                let samples = Array(record.samples.dropFirst(Int(skip)))
                continuation.yield(AudioChunk(samples: samples,
                                              startSample: max(record.start, fromSample), source: kind))
            }
            continuation.finish()
        }
    }

    func sessionsWithJournals() async -> [SessionID] {
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return Array(Set(entries.compactMap { url -> SessionID? in
            guard url.pathExtension == "journal" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            // Session IDs are UUIDs, so split on the *last* hyphen before the source name.
            guard let separator = name.lastIndex(of: "-") else { return nil }
            return SessionID(String(name[..<separator]))
        })).sorted { $0.value < $1.value }
    }

    func sampleCount(session: SessionID, source: AudioSourceKind) async -> Int64 {
        Self.records(at: file(session, source)).map(\.end).max() ?? 0
    }

    func delete(session: SessionID) async {
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("\(session.value)-") {
            try? fileManager.removeItem(at: url)
        }
    }

    func freeBytes() async -> Int64 { Int64.max }

    func appendRecord(_ chunk: AudioChunk, to url: URL) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var start = chunk.startSample.littleEndian
        var count = UInt32(chunk.samples.count).littleEndian
        try withUnsafeBytes(of: &start) { try handle.write(contentsOf: Data($0)) }
        try withUnsafeBytes(of: &count) { try handle.write(contentsOf: Data($0)) }
        var data = Data()
        for sample in chunk.samples {
            var value = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    func tear(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xFF, 0xFF])) // a partial record header
        try handle.synchronize()
    }

    private struct Record {
        let start: Int64
        let end: Int64
        let samples: [Float]
    }

    private static func records(at url: URL) -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        var result: [Record] = []
        var offset = 0
        while offset + 12 <= data.count {
            let start = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian }
            let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self).littleEndian })
            let byteCount = count * MemoryLayout<Float>.size
            guard count > 0, count < 10_000_000, offset + 12 + byteCount <= data.count else { break }
            var samples: [Float] = []
            samples.reserveCapacity(count)
            for i in 0..<count {
                let byte = offset + 12 + i * MemoryLayout<Float>.size
                let float = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: byte, as: UInt32.self).littleEndian }
                samples.append(Float(bitPattern: float))
            }
            result.append(Record(start: Int64(bitPattern: start), end: Int64(bitPattern: start) + Int64(count), samples: samples))
            offset += 12 + byteCount
        }
        return result
    }
}

private actor FileBackedJournalWriter: AudioJournalWriter {
    private unowned let store: FileBackedJournalStore
    private let url: URL
    private let source: AudioSourceKind
    private var total: Int64 = 0
    private var degraded = false

    init(store: FileBackedJournalStore, url: URL, source: AudioSourceKind) {
        self.store = store
        self.url = url
        self.source = source
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    func append(_ chunk: AudioChunk) async {
        guard chunk.source == source else { return }
        do {
            try await store.appendRecord(chunk, to: url)
            total = max(total, chunk.endSample)
        } catch { degraded = true }
    }

    func close() async -> JournalSummary { JournalSummary(samples: total, degraded: degraded) }
    var isDegraded: Bool { degraded }
}

enum RecoveryTestSupport {
    static func tempRoot(_ label: String = "recovery") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuperflowRecovery-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func chunks(_ count: Int, source: AudioSourceKind = .mic, samples: Int = 1_600) -> [AudioChunk] {
        (0..<count).map { i in
            AudioChunk(samples: Array(repeating: 0.25, count: samples),
                       startSample: Int64(i * samples), source: source)
        }
    }

    static func engine(repository: any TranscriptRepository, journals: any JournalStore,
                       recognizer: any SpeechRecognizer, root: URL,
                       keepJournals: Bool = false, cleaner: RecoveryCleaner? = nil,
                       clock: any TimeSource = SystemTimeSource(),
                       budget: Duration = .seconds(30),
                       fault: RecoveryFaultInjector? = nil) -> RecoveryEngine {
        RecoveryEngine(repository: repository, journals: journals, recognizer: recognizer,
                       clock: clock, keepJournals: keepJournals, cleaner: cleaner,
                       stateRoot: root.appendingPathComponent("State", isDirectory: true),
                       lockRoot: root.appendingPathComponent("Locks", isDirectory: true),
                       recoveryBudget: budget, fault: fault)
    }
}
