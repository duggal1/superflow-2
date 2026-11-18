import Foundation
import os
import SuperflowPorts

// MARK: - Counters

/// Fixed-size snapshot of health counters. No arrays, no strings from callers
/// other than the sanitized model revision, so export cost is constant.
public struct CounterSnapshot: Codable, Sendable, Equatable {
    public var ringOverflows: UInt64
    public var audioDiscontinuities: UInt64
    public var deadlineMisses: UInt64
    public var maxQueueAgeMs: Double
    public var modelRevision: String
    public var modelRevisionChanges: UInt64

    public init(ringOverflows: UInt64 = 0,
                audioDiscontinuities: UInt64 = 0,
                deadlineMisses: UInt64 = 0,
                maxQueueAgeMs: Double = 0,
                modelRevision: String = "unspecified",
                modelRevisionChanges: UInt64 = 0) {
        self.ringOverflows = ringOverflows
        self.audioDiscontinuities = audioDiscontinuities
        self.deadlineMisses = deadlineMisses
        self.maxQueueAgeMs = DiagnosticSanitizer.finite(maxQueueAgeMs)
        self.modelRevision = DiagnosticSanitizer.token(modelRevision)
        self.modelRevisionChanges = modelRevisionChanges
    }
}

/// Monotonic, bounded, lock-protected health counters.
///
/// Every mutator is non-throwing and non-trapping. Counters use wrapping
/// addition so a very long session can never overflow into a crash, and a
/// module can call them from the audio path without an allocation or a wait
/// on anything outside this object.
public final class DiagnosticsCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var ringOverflows: UInt64 = 0
    private var audioDiscontinuities: UInt64 = 0
    private var deadlineMisses: UInt64 = 0
    private var maxQueueAgeMs: Double = 0
    private var modelRevision: String = "unspecified"
    private var modelRevisionChanges: UInt64 = 0

    public init() {}

    public func noteRingOverflow() {
        lock.withLock { ringOverflows &+= 1 }
    }

    public func noteAudioDiscontinuity() {
        lock.withLock { audioDiscontinuities &+= 1 }
    }

    public func noteDeadlineMiss() {
        lock.withLock { deadlineMisses &+= 1 }
    }

    /// Records the worst observed queue age; the snapshot stays one double no
    /// matter how many samples arrive.
    public func observeQueueAgeMs(_ ms: Double) {
        let value = DiagnosticSanitizer.finite(ms)
        lock.withLock { if value > maxQueueAgeMs { maxQueueAgeMs = value } }
    }

    /// Stores a sanitized revision token and counts distinct revisions seen.
    /// A path or a prose description becomes an opaque hash, never text.
    public func setModelRevision(_ revision: String) {
        let token = DiagnosticSanitizer.token(revision)
        lock.withLock {
            guard token != modelRevision else { return }
            modelRevision = token
            modelRevisionChanges &+= 1
        }
    }

    public var snapshot: CounterSnapshot {
        lock.withLock {
            CounterSnapshot(ringOverflows: ringOverflows,
                            audioDiscontinuities: audioDiscontinuities,
                            deadlineMisses: deadlineMisses,
                            maxQueueAgeMs: maxQueueAgeMs,
                            modelRevision: modelRevision,
                            modelRevisionChanges: modelRevisionChanges)
        }
    }

    public func reset() {
        lock.withLock {
            ringOverflows = 0
            audioDiscontinuities = 0
            deadlineMisses = 0
            maxQueueAgeMs = 0
            modelRevision = "unspecified"
            modelRevisionChanges = 0
        }
    }
}

// MARK: - Bounded ring

/// Bounded, lock-protected local metrics. Never contains transcript text;
/// every name, device and field is sanitized on the way in. The buffers are
/// capped, so memory does not grow with session duration.
public final class MetricsRing: MetricsSink, @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var metrics: [MetricSample] = []
    private var events: [MetricEvent] = []
    private var sequence: UInt64 = 0

    /// Shared health counters; the ring feeds ring-overflow events here.
    public let counters: DiagnosticsCounters

    public init(capacity: Int = 2_000, counters: DiagnosticsCounters = DiagnosticsCounters()) {
        self.capacity = max(1, capacity)
        self.counters = counters
    }

    public func record(_ name: String, valueMs: Double) {
        record(name, valueMs: valueMs, device: "local")
    }

    /// Tags a timing with a sanitized device or model token for per-device
    /// summaries. Nothing here throws, allocates beyond one bounded sample,
    /// or waits on anything but this ring's short lock.
    public func record(_ name: String, valueMs: Double, device: String) {
        // Fail open: a non-finite duration is meaningless and must never reach
        // an export or a percentile calculation, so it is simply ignored.
        guard valueMs.isFinite else { return }
        let sample = MetricSample(name: name, valueMs: valueMs, device: device)
        lock.withLock {
            metrics.append(sample)
            if metrics.count > capacity {
                metrics.removeFirst(metrics.count - capacity)
                counters.noteRingOverflow()
            }
        }
    }

    public func event(_ name: String, _ fields: [String: String]) {
        lock.withLock {
            sequence &+= 1
            events.append(MetricEvent(name: name, fields: fields, sequence: sequence))
            if events.count > capacity {
                events.removeFirst(events.count - capacity)
                counters.noteRingOverflow()
            }
        }
    }

    public var snapshot: (metrics: [MetricSample], events: [MetricEvent]) {
        lock.withLock { (metrics, events) }
    }

    /// Incremental, bounded reader. Returns at most `limit` events newer than
    /// the given sequence number, so a consumer can make progress without
    /// copying or reparsing the whole ring.
    public func events(after sequence: UInt64, limit: Int = 200) -> [MetricEvent] {
        lock.withLock {
            Array(events.lazy.filter { $0.sequence > sequence }.prefix(max(0, limit)))
        }
    }

    public func reset() {
        lock.withLock {
            metrics.removeAll()
            events.removeAll()
            sequence = 0
        }
    }
}
