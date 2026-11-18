import Foundation
import os
import SuperflowPorts

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
