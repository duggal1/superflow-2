import Foundation
import SuperflowKernel

public enum AudioEvent: Sendable, Equatable {
    case routeChanged
    case failed(String)
    case permissionRevoked
    case stopped
}

public struct AudioStreams: Sendable {
    public let samples: AsyncStream<AudioChunk>
    public let events: AsyncStream<AudioEvent>
    public init(samples: AsyncStream<AudioChunk>, events: AsyncStream<AudioEvent>) {
        self.samples = samples
        self.events = events
    }
}

/// 16 kHz mono Float32, sample-count timestamps starting at 0 for each start().
public protocol AudioSource: Sendable {
    var kind: AudioSourceKind { get }
    func start() async throws -> AudioStreams
    func stop() async
}

public struct JournalSummary: Sendable, Equatable {
    public var samples: Int64
    public var degraded: Bool
    public init(samples: Int64, degraded: Bool) {
        self.samples = samples
        self.degraded = degraded
    }
}

public protocol AudioJournalWriter: Sendable {
    func append(_ chunk: AudioChunk) async
    func close() async -> JournalSummary
    var isDegraded: Bool { get async }
}

/// A finished dictation clip: the audio the recognizer actually heard, plus the
/// waveform peaks computed while writing so the player never decodes to draw.
public struct ArchivedAudio: Sendable, Equatable {
    public let url: URL
    public let duration: TimeInterval
    /// 20 peaks per second, one byte each, 0...255.
    public let peaks: [UInt8]
    public init(url: URL, duration: TimeInterval, peaks: [UInt8]) {
        self.url = url
        self.duration = duration
        self.peaks = peaks
    }
}

/// Copies samples and returns. Encoding and disk I/O happen elsewhere.
public protocol AudioArchiveWriter: Sendable {
    func append(_ chunk: AudioChunk) async
    /// Closes the file. Returns nil when nothing usable was written.
    func finish() async -> ArchivedAudio?
    func discard() async
}

public protocol AudioArchiveStore: Sendable {
    func makeWriter(session: SessionID) async throws -> any AudioArchiveWriter
    func delete(session: SessionID) async
    /// Removes clips older than the retention setting. Nil means keep forever.
    func sweep(olderThanDays days: Int?) async
}

public protocol JournalStore: Sendable {
    /// Opens a lane whose first sample is `startingSample` on the shared session clock. Mic lanes
    /// start at 0; the meeting system lane starts at its shared-clock offset so journaled sample
    /// positions match the committed transcript timestamps.
    func openWriter(session: SessionID, source: AudioSourceKind, startingSample: Int64) async throws -> any AudioJournalWriter
    func replay(session: SessionID, source: AudioSourceKind, fromSample: Int64) async -> AsyncStream<AudioChunk>
    func sessionsWithJournals() async -> [SessionID]
    /// The journal's end position on the shared clock, i.e. the absolute sample just past the last
    /// journaled sample. Recovery compares this against committed segment timestamps, so it must
    /// include any starting offset rather than only count journaled samples.
    func sampleCount(session: SessionID, source: AudioSourceKind) async -> Int64
    func delete(session: SessionID) async
    func freeBytes() async -> Int64
}

public extension JournalStore {
    func openWriter(session: SessionID, source: AudioSourceKind) async throws -> any AudioJournalWriter {
        try await openWriter(session: session, source: source, startingSample: 0)
    }
}
