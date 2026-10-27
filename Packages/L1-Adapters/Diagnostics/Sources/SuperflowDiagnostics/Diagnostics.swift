import Foundation
import os
import SuperflowPorts

public struct MetricSample: Codable, Sendable, Equatable {
    public var name: String
    public var valueMs: Double
    public var at: Date
    public init(name: String, valueMs: Double, at: Date = Date()) {
        self.name = name
        self.valueMs = valueMs
        self.at = at
    }
}

public struct MetricEvent: Codable, Sendable, Equatable {
    public var name: String
    public var fields: [String: String]
    public var at: Date
    public init(name: String, fields: [String: String], at: Date = Date()) {
        self.name = name
        self.fields = fields
        self.at = at
    }
}

/// Bounded, lock-protected local metrics. Never contains transcript text; call
/// sites pass durations and stage names only.
public final class MetricsRing: MetricsSink, @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var metrics: [MetricSample] = []
    private var events: [MetricEvent] = []

    public init(capacity: Int = 2_000) {
        self.capacity = max(1, capacity)
    }

    public func record(_ name: String, valueMs: Double) {
        lock.withLock {
            metrics.append(MetricSample(name: name, valueMs: valueMs))
            if metrics.count > capacity { metrics.removeFirst(metrics.count - capacity) }
        }
    }

    public func event(_ name: String, _ fields: [String: String]) {
        lock.withLock {
            events.append(MetricEvent(name: name, fields: fields))
            if events.count > capacity { events.removeFirst(events.count - capacity) }
        }
    }

    public var snapshot: (metrics: [MetricSample], events: [MetricEvent]) {
        lock.withLock { (metrics, events) }
    }

    public func reset() {
        lock.withLock {
            metrics.removeAll()
            events.removeAll()
        }
    }
}

/// One os.Logger category per module, plus signposts for stage timing.
public struct DiagnosticsLogger: @unchecked Sendable {
    private let logger: Logger
    private let signposter: OSSignposter

    public init(category: String, subsystem: String = "com.superflow.app") {
        logger = Logger(subsystem: subsystem, category: category)
        signposter = OSSignposter(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// Speech-derived text must use this overload so it stays out of logs.
    public func privateInfo(_ message: String) {
        logger.info("\(message, privacy: .private)")
    }

    @discardableResult
    public func begin(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: id)
    }

    public func end(_ name: StaticString, state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}

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

    public init(generatedAt: String, appVersion: String, appBuild: String, os: String,
                architecture: String, databaseBytes: Int64?, metrics: [MetricSample],
                events: [MetricEvent], notes: [String]) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.os = os
        self.architecture = architecture
        self.databaseBytes = databaseBytes
        self.metrics = metrics
        self.events = events
        self.notes = notes
    }
}

public struct DiagnosticsExporter: DiagnosticsExporting {
    private let metrics: MetricsRing
    private let databaseURL: URL?

    public init(metrics: MetricsRing, databaseURL: URL? = nil) {
        self.metrics = metrics
        self.databaseURL = databaseURL
    }

    public func exportDiagnostics(to url: URL) async throws {
        let snapshot = metrics.snapshot
        let info = Bundle.main.infoDictionary
        let payload = DiagnosticsPayload(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "dev",
            appBuild: info?["CFBundleVersion"] as? String ?? "0",
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            databaseBytes: databaseBytes(),
            metrics: snapshot.metrics,
            events: snapshot.events,
            notes: ["No speech text, audio, model files or network telemetry are included."])

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
