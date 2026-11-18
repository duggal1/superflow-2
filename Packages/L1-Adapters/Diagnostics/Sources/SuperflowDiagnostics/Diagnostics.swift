import Foundation
import os
import SuperflowPorts

// MARK: - Sanitization

/// Turns arbitrary caller strings into short, content-free tokens.
///
/// Diagnostics is strictly local. User audio, transcripts, window titles, file
/// paths and free-form prose must never reach a log, a signpost or an exported
/// file. Every string entering the diagnostics package passes through here.
/// Input that is not already a plain identifier is replaced by a hash, so a
/// transcript fragment can never survive by simply dropping its punctuation.
enum DiagnosticSanitizer {
    /// Longest identifier accepted verbatim. Longer identifiers are hashed.
    static let tokenLimit = 64
    /// Longest event field value retained.
    static let fieldValueLimit = 96
    /// Hard cap on fields per event.
    static let maxFields = 12

    static func token(_ raw: String, limit: Int = tokenLimit, fallback: String = "unspecified") -> String {
        let cap = max(1, limit)
        var kept: [UInt8] = []
        kept.reserveCapacity(cap)
        var sawOther = false
        var exhausted = false
        // Scan at most `cap` bytes. A hostile multi-megabyte string can never
        // make an audio callback do work proportional to its length.
        for byte in raw.utf8 {
            if kept.count >= cap { exhausted = true; break }
            guard Self.isAllowed(byte) else { sawOther = true; break }
            kept.append(byte)
        }
        guard !sawOther, !exhausted else { return hashToken(kept) }
        return kept.isEmpty ? fallback : String(decoding: kept, as: UTF8.self)
    }

    /// Bounded-by-construction copy: scans at most `limit` UTF-8 bytes, so a
    /// hostile or enormous string can never make diagnostics do unbounded work
    /// on an audio or UI thread.
    static func bounded(_ raw: String, limit: Int) -> String {
        String(decoding: raw.utf8.prefix(max(0, limit)), as: UTF8.self)
    }

    /// NaN and infinity are converted to a finite value before they can reach
    /// an export or a percentile calculation (a trap there would be a crash).
    static func finite(_ value: Double, fallback: Double = 0) -> Double {
        value.isFinite ? value : fallback
    }

    static func fields(_ raw: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in raw.prefix(maxFields).sorted(by: { $0.key < $1.key }) {
            result[token(key, limit: 48)] = token(value, limit: fieldValueLimit, fallback: "set")
        }
        return result
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
        (byte >= 48 && byte <= 57) || byte == 46 || byte == 95 || byte == 45
    }

    /// FNV-1a over raw bytes, rendered as a short opaque label. Used whenever
    /// input contains characters an identifier cannot have (spaces, quotes,
    /// path separators), which is the shape user content takes.
    private static func hashToken(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0100_0000_01b3
        }
        let hex = String(UInt32(truncatingIfNeeded: hash), radix: 16)
        return "h" + String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }
}

// MARK: - Samples and events

public struct MetricSample: Codable, Sendable, Equatable {
    public var name: String
    public var valueMs: Double
    public var at: Date
    /// Sanitized device label. Defaults to the single local device; callers may
    /// supply a token to group timings per audio device or model revision.
    public var device: String

    public init(name: String, valueMs: Double, device: String = "local", at: Date = Date()) {
        self.name = DiagnosticSanitizer.token(name)
        self.valueMs = DiagnosticSanitizer.finite(valueMs)
        self.device = DiagnosticSanitizer.token(device)
        self.at = at
    }
}

public struct MetricEvent: Codable, Sendable, Equatable {
    public var name: String
    public var fields: [String: String]
    public var at: Date
    /// Monotonic sequence number, so a bounded reader can make incremental
    /// progress without rereading or trusting wall-clock timestamps.
    public var sequence: UInt64

    public init(name: String, fields: [String: String], at: Date = Date(), sequence: UInt64 = 0) {
        self.name = DiagnosticSanitizer.token(name)
        self.fields = DiagnosticSanitizer.fields(fields)
        self.at = at
        self.sequence = sequence
    }
}

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

// MARK: - Logging and signposts

/// One os.Logger category per pipeline module, matching the sanitized
/// diagnostics the ring collects.
public enum DiagnosticsModule: String, Sendable, CaseIterable {
    case capture
    case journal
    case enhancement
    case vad
    case asr
    case text
    case insertion
    case recovery

    public var category: String { "superflow.\(rawValue)" }
}

/// Stable signpost names for the pipeline stages. Call sites pass one of these
/// to `DiagnosticsLogger.measure` so Instruments shows the same interval name
/// in every session and no free-form text can enter a signpost.
public enum DiagnosticsStage {
    public static let capture: StaticString = "superflow.capture"
    public static let journal: StaticString = "superflow.journal"
    public static let enhancement: StaticString = "superflow.enhancement"
    public static let vad: StaticString = "superflow.vad"
    public static let asr: StaticString = "superflow.asr"
    public static let text: StaticString = "superflow.text"
    public static let insertion: StaticString = "superflow.insertion"
    public static let recovery: StaticString = "superflow.recovery"
}

/// A process-wide logger per module. Instances are created once; signposting
/// on a hot path is a timestamp plus two atomic writes, with no I/O.
public enum DiagnosticsLoggers {
    public static let subsystem = "com.superflow.app"

    public static let capture = DiagnosticsLogger(module: .capture)
    public static let journal = DiagnosticsLogger(module: .journal)
    public static let enhancement = DiagnosticsLogger(module: .enhancement)
    public static let vad = DiagnosticsLogger(module: .vad)
    public static let asr = DiagnosticsLogger(module: .asr)
    public static let text = DiagnosticsLogger(module: .text)
    public static let insertion = DiagnosticsLogger(module: .insertion)
    public static let recovery = DiagnosticsLogger(module: .recovery)

    public static func logger(for module: DiagnosticsModule) -> DiagnosticsLogger {
        switch module {
        case .capture: return capture
        case .journal: return journal
        case .enhancement: return enhancement
        case .vad: return vad
        case .asr: return asr
        case .text: return text
        case .insertion: return insertion
        case .recovery: return recovery
        }
    }
}

public struct DiagnosticsLogger: @unchecked Sendable {
    private let logger: Logger
    private let signposter: OSSignposter

    public init(category: String, subsystem: String = DiagnosticsLoggers.subsystem) {
        logger = Logger(subsystem: subsystem, category: DiagnosticSanitizer.token(category))
        signposter = OSSignposter(subsystem: subsystem, category: DiagnosticSanitizer.token(category))
    }

    public init(module: DiagnosticsModule, subsystem: String = DiagnosticsLoggers.subsystem) {
        self.init(category: module.category, subsystem: subsystem)
    }

    /// Static metadata only. Never pass transcripts or audio-derived text here.
    public func info(_ message: String) {
        logger.info("\(DiagnosticSanitizer.token(message), privacy: .public)")
    }

    public func debug(_ message: String) {
        logger.debug("\(DiagnosticSanitizer.token(message), privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(DiagnosticSanitizer.token(message), privacy: .public)")
    }

    /// Speech-derived text must use this overload so it stays out of logs.
    public func privateInfo(_ message: String) {
        logger.info("\(DiagnosticSanitizer.bounded(message, limit: DiagnosticSanitizer.fieldValueLimit), privacy: .private)")
    }

    @discardableResult
    public func begin(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: id)
    }

    public func end(_ name: StaticString, state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// Wraps a stage in a signpost interval. `defer` guarantees the interval is
    /// closed even when the body throws, and diagnostics never alter the
    /// body's result or insert a failure of its own.
    @discardableResult
    public func measure<T>(_ name: StaticString, body: () throws -> T) rethrows -> T {
        let state = begin(name)
        defer { end(name, state: state) }
        return try body()
    }
}

// MARK: - Timing summary

/// Percentiles for one (device, metric) group. Contains durations and opaque
/// labels only — no samples, text, paths or timestamps.
public struct TimingPercentiles: Codable, Sendable, Equatable {
    public var device: String
    public var metric: String
    public var count: Int
    public var minMs: Double
    public var p50Ms: Double
    public var p95Ms: Double
    public var p99Ms: Double
    public var maxMs: Double

    public init(device: String,
                metric: String,
                count: Int,
                minMs: Double,
                p50Ms: Double,
                p95Ms: Double,
                p99Ms: Double,
                maxMs: Double) {
        self.device = DiagnosticSanitizer.token(device)
        self.metric = DiagnosticSanitizer.token(metric)
        self.count = max(0, count)
        self.minMs = DiagnosticSanitizer.finite(minMs)
        self.p50Ms = DiagnosticSanitizer.finite(p50Ms)
        self.p95Ms = DiagnosticSanitizer.finite(p95Ms)
        self.p99Ms = DiagnosticSanitizer.finite(p99Ms)
        self.maxMs = DiagnosticSanitizer.finite(maxMs)
    }
}

/// Builds a bounded, deterministic per-device timing summary. Group count is
/// capped so a long session with many metric names cannot grow the export.
public enum TimingSummaryBuilder {
    public static let maxGroups = 64

    public static func build(from samples: [MetricSample], maxGroups: Int = TimingSummaryBuilder.maxGroups) -> [TimingPercentiles] {
        struct Key: Hashable { let device: String; let metric: String }
        var grouped: [Key: [Double]] = [:]
        for sample in samples {
            let value = DiagnosticSanitizer.finite(sample.valueMs, fallback: -1)
            guard value >= 0 else { continue }
            let key = Key(device: DiagnosticSanitizer.token(sample.device),
                          metric: DiagnosticSanitizer.token(sample.name))
            grouped[key, default: []].append(value)
        }
        let ordered = grouped.keys.sorted { lhs, rhs in
            lhs.device == rhs.device ? lhs.metric < rhs.metric : lhs.device < rhs.device
        }
        return ordered.prefix(max(0, maxGroups)).map { key in
            let values = grouped[key]!.sorted()
            return TimingPercentiles(device: key.device,
                                     metric: key.metric,
                                     count: values.count,
                                     minMs: values[0],
                                     p50Ms: percentile(values, 0.50),
                                     p95Ms: percentile(values, 0.95),
                                     p99Ms: percentile(values, 0.99),
                                     maxMs: values[values.count - 1])
        }
    }

    /// Nearest-rank percentile. Returns a finite value for any input.
    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[max(0, min(sorted.count - 1, rank))]
    }
}

// MARK: - Export

public struct DiagnosticsPayload: Codable, Sendable {
    public var generatedAt: String
    public var appVersion: String
    public var appBuild: String
    public var os: String
    public var architecture: String
    public var databaseBytes: Int64?
    public var metrics: [MetricSample]
    public var events: [MetricEvent]
    public var notes: [String]
    public var counters: CounterSnapshot
    public var timing: [TimingPercentiles]

    public init(generatedAt: String, appVersion: String, appBuild: String, os: String,
                architecture: String, databaseBytes: Int64?, metrics: [MetricSample],
                events: [MetricEvent], notes: [String],
                counters: CounterSnapshot = CounterSnapshot(),
                timing: [TimingPercentiles] = []) {
        self.generatedAt = DiagnosticSanitizer.bounded(generatedAt, limit: 40)
        self.appVersion = DiagnosticSanitizer.token(appVersion, limit: 40)
        self.appBuild = DiagnosticSanitizer.token(appBuild, limit: 40)
        self.os = DiagnosticSanitizer.bounded(os, limit: DiagnosticSanitizer.fieldValueLimit)
        self.architecture = DiagnosticSanitizer.token(architecture, limit: 24)
        self.databaseBytes = databaseBytes
        self.metrics = metrics
        self.events = events
        self.notes = Array(notes.prefix(4))
        self.counters = counters
        self.timing = Array(timing.prefix(TimingSummaryBuilder.maxGroups))
    }
}

public struct DiagnosticsExporter: DiagnosticsExporting {
    /// Fixed notice, never constructed from user data.
    public static let notice = "No speech text, audio, model files or network telemetry are included."

    private let metrics: MetricsRing
    private let databaseURL: URL?

    public init(metrics: MetricsRing, databaseURL: URL? = nil) {
        self.metrics = metrics
        self.databaseURL = databaseURL
    }

    public func exportDiagnostics(to url: URL) async throws {
        let snapshot = metrics.snapshot
        let payload = DiagnosticsPayload(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            databaseBytes: databaseBytes(),
            metrics: snapshot.metrics,
            events: snapshot.events,
            notes: [Self.notice],
            counters: metrics.counters.snapshot,
            timing: TimingSummaryBuilder.build(from: snapshot.metrics))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func databaseBytes() -> Int64? {
        guard let databaseURL else { return nil }
        let candidates = [databaseURL,
                          URL(fileURLWithPath: databaseURL.path + "-wal"),
                          URL(fileURLWithPath: databaseURL.path + "-shm")]
        var total: Int64 = 0
        var found = false
        for url in candidates {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            total += Int64(size)
            found = true
        }
        return found ? total : nil
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
