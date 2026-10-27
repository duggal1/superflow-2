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
