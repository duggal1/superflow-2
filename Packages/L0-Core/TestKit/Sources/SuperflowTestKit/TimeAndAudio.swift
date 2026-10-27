import Foundation
import SuperflowKernel
import SuperflowPorts

public final class ManualTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var ns: UInt64 = 0
    public init() {}
    public func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(monotonicNs()) / 1e9) }
    public func monotonicNs() -> UInt64 { lock.lock(); defer { lock.unlock() }; return ns }
    public func advance(ms: Int) {
        lock.lock()
        ns += UInt64(max(0, ms)) * 1_000_000
        lock.unlock()
    }
}

public final class ReplayAudioSource: AudioSource, @unchecked Sendable {
    public let kind: AudioSourceKind
    private let samples: [Float]
    private let chunkSamples: Int
    private let taskLock = NSLock()
    private var task: Task<Void, Never>?

    public init(samples: [Float], kind: AudioSourceKind = .mic, chunkSamples: Int = 1_600) {
        self.samples = samples
        self.kind = kind
        self.chunkSamples = chunkSamples
    }

    public func start() async throws -> AudioStreams {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(600))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let all = samples
        let n = chunkSamples
        let k = kind
        let t = Task {
            var i = 0
            while i < all.count && !Task.isCancelled {
                let j = min(all.count, i + n)
                continuation.yield(AudioChunk(samples: Array(all[i..<j]), startSample: Int64(i), source: k))
                i = j
            }
            continuation.finish()
            eventContinuation.yield(.stopped)
            eventContinuation.finish()
        }
        taskLock.withLock { task = t }
        return AudioStreams(samples: stream, events: events)
    }

    public func stop() async {
        let t = taskLock.withLock { () -> Task<Void, Never>? in
            let current = task
            task = nil
            return current
        }
        t?.cancel()
    }
}

/// Emits one committed segment per `samplesPerSegment` fed. Deterministic, ordered, finish-safe.
public final class FakeRecognitionStream: RecognitionStream, @unchecked Sendable {
    public let events: AsyncStream<RecognitionEvent>
    private let continuation: AsyncStream<RecognitionEvent>.Continuation
    private let lock = NSLock()
    private var fed: Int64 = 0
    private var segmentStart: Int64 = 0
    private var index = 0
    private var isFinished = false
    private let script: [String]
    private let samplesPerSegment: Int64
    private let source: AudioSourceKind
    private let failEvery: Int

    public init(script: [String], samplesPerSegment: Int = 80_000, source: AudioSourceKind = .mic, failEvery: Int = 0) {
        (events, continuation) = AsyncStream<RecognitionEvent>.makeStream(bufferingPolicy: .bufferingNewest(8_192))
        self.script = script
        self.samplesPerSegment = Int64(samplesPerSegment)
        self.source = source
        self.failEvery = failEvery
    }

    public func feed(_ chunk: AudioChunk) async {
        let output: [RecognitionEvent] = lock.withLock { enqueue(chunk) }
        for event in output { continuation.yield(event) }
    }

    private func enqueue(_ chunk: AudioChunk) -> [RecognitionEvent] {
        guard !isFinished else { return [] }
        fed = max(fed, chunk.endSample)
        if index > 0, failEvery > 0, index % failEvery == 0 {
            index += 1
            return [.failure("injected ASR failure")]
        }
        guard fed - segmentStart >= samplesPerSegment else { return [] }
        let start = segmentStart
        let end = fed
        let text = script.isEmpty ? "segment \(index)" : script[index % script.count]
        index += 1
        segmentStart = end
        return [
            .partial(text),
            .committed(RawSegment(text: text, startSample: start, endSample: end, source: source)),
            .endpoint(end),
        ]
    }

    public func finish() async {
        let output: [RecognitionEvent] = lock.withLock {
            guard !isFinished else { return [] }
            isFinished = true
            let start = segmentStart
            let end = fed
            let text = script.isEmpty ? "segment \(index)" : script[index % script.count]
            guard end > start else { return [] }
            return [.committed(RawSegment(text: text, startSample: start, endSample: end, source: source))]
        }
        for event in output { continuation.yield(event) }
        continuation.finish()
    }
}


/// Emits a fixed PCM buffer immediately, then finishes. Deterministic for engine tests.
public final class ScriptedAudioSource: AudioSource, @unchecked Sendable {
    public let kind: AudioSourceKind
    private let samples: [Float]
    private let chunkSamples: Int
    private let failStart: Bool
    private let lock = NSLock()
    private var started = 0
    private var stopped = 0

    public init(samples: [Float], kind: AudioSourceKind = .mic, chunkSamples: Int = 1_600,
                failStart: Bool = false) {
        self.samples = samples
        self.kind = kind
        self.chunkSamples = chunkSamples
        self.failStart = failStart
    }

    public var startCount: Int { lock.withLock { started } }
    public var stopCount: Int { lock.withLock { stopped } }

    public func start() async throws -> AudioStreams {
        if failStart { throw SuperflowError.audioFailure("scripted start failure") }
        lock.withLock { started += 1 }
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(4096))
        let (events, eventContinuation) = AsyncStream<AudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        var i = 0
        while i < samples.count {
            let j = min(samples.count, i + chunkSamples)
            continuation.yield(AudioChunk(samples: Array(samples[i..<j]), startSample: Int64(i), source: kind))
            i = j
        }
        continuation.finish()
        eventContinuation.yield(.stopped)
        eventContinuation.finish()
        return AudioStreams(samples: stream, events: events)
    }

    public func stop() async {
        lock.withLock { stopped += 1 }
    }
}
