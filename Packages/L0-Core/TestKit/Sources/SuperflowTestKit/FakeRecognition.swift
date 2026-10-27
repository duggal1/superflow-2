import Foundation
import SuperflowKernel
import SuperflowPorts

public actor FakeJournalStore: JournalStore {
    public private(set) var chunks: [AudioSourceKind: [AudioChunk]] = [:]
    public var shouldFail = false
    /// Fails only the listed sources, so a test can make a single lane (for example the meeting
    /// system lane) hit a full disk while the microphone lane still opens.
    public var failSources: Set<AudioSourceKind> = []
    public var free = Int64.max

    public init() {}

    public func setShouldFail(_ value: Bool) { shouldFail = value }
    public func setFailSources(_ sources: Set<AudioSourceKind>) { failSources = sources }

    public func openWriter(session: SessionID, source: AudioSourceKind,
                           startingSample: Int64) async throws -> any AudioJournalWriter {
        if shouldFail || failSources.contains(source) { throw SuperflowError.diskFull }
        return FakeJournalWriter(store: self, source: source)
    }

    public func record(_ chunk: AudioChunk) {
        chunks[chunk.source, default: []].append(chunk)
    }

    public func replay(session: SessionID, source: AudioSourceKind, fromSample: Int64) async -> AsyncStream<AudioChunk> {
        let all = (chunks[source] ?? []).filter { $0.endSample > fromSample }.map {
            AudioChunk(samples: Array($0.samples.dropFirst(max(0, Int(fromSample - $0.startSample)))),
                       startSample: max($0.startSample, fromSample), source: $0.source)
        }
        return AsyncStream { cont in
            for c in all { cont.yield(c) }
            cont.finish()
        }
    }

    public func sessionsWithJournals() async -> [SessionID] { [] }
    /// End position on the shared clock, matching the real journal's contract.
    public func sampleCount(session: SessionID, source: AudioSourceKind) async -> Int64 {
        (chunks[source] ?? []).reduce(0) { max($0, $1.endSample) }
    }
    public func delete(session: SessionID) async { chunks.removeAll() }
    public func freeBytes() async -> Int64 { free }
}

public actor FakeJournalWriter: AudioJournalWriter {
    private unowned let store: FakeJournalStore
    private var total: Int64 = 0
    private var degraded = false
    public init(store: FakeJournalStore, source: AudioSourceKind) { self.store = store }

    public func append(_ chunk: AudioChunk) async {
        await store.record(chunk)
        total = max(total, chunk.endSample)
    }
    public func close() async -> JournalSummary { JournalSummary(samples: total, degraded: degraded) }
    public var isDegraded: Bool { degraded }
}

public actor FakePermissionGate: PermissionGate {
    private var map: [Permission: PermissionStatus]
    private var continuation: AsyncStream<(Permission, PermissionStatus)>.Continuation?
    public private(set) var requested: [Permission] = []
    public private(set) var opened: [Permission] = []
    public init(all status: PermissionStatus = .granted) {
        map = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, status) })
    }
    public func set(_ p: Permission, _ s: PermissionStatus) {
        map[p] = s
        continuation?.yield((p, s))
    }
    public func status(_ p: Permission) async -> PermissionStatus { map[p] ?? .notDetermined }
    public func request(_ p: Permission) async -> PermissionStatus {
        requested.append(p)
        return map[p] ?? .notDetermined
    }
    public func openSystemSettings(_ p: Permission) async { opened.append(p) }
    public func updates() async -> AsyncStream<(Permission, PermissionStatus)> {
        AsyncStream { cont in self.continuation = cont }
    }
}

public final class FakeHotkeySource: HotkeySource, @unchecked Sendable {
    public let events: AsyncStream<KeyEvent>
    private let continuation: AsyncStream<KeyEvent>.Continuation
    public private(set) var activeTap = false
    public init() {
        (events, continuation) = AsyncStream<KeyEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
    }
    public func start() async throws {}
    public func stop() async { continuation.finish() }
    public func setActiveTap(_ on: Bool) async { activeTap = on }
    public func send(_ e: KeyEvent) { continuation.yield(e) }
}


public actor FakeSpeechRecognizer: SpeechRecognizer {
    public private(set) var isReady: Bool
    public var script: [String]
    public var scriptsBySource: [AudioSourceKind: [String]]
    public var samplesPerSegment: Int
    public var failWarmUp: Bool
    public var failMakeStream: Bool
    public private(set) var streamsMade = 0

    public init(isReady: Bool = true, script: [String] = ["hello world"],
                scriptsBySource: [AudioSourceKind: [String]] = [:],
                samplesPerSegment: Int = 80_000, failWarmUp: Bool = false,
                failMakeStream: Bool = false) {
        self.isReady = isReady
        self.script = script
        self.scriptsBySource = scriptsBySource
        self.samplesPerSegment = samplesPerSegment
        self.failWarmUp = failWarmUp
        self.failMakeStream = failMakeStream
    }

    public func warmUp(profile: String) async throws {
        if failWarmUp { throw SuperflowError.modelUnavailable(profile) }
        isReady = true
    }

    public func makeStream(profile: String, source: AudioSourceKind) async throws -> any RecognitionStream {
        if failMakeStream { throw SuperflowError.modelUnavailable(profile) }
        streamsMade += 1
        let selected = scriptsBySource[source] ?? script
        return FakeRecognitionStream(script: selected, samplesPerSegment: samplesPerSegment, source: source)
    }
}
