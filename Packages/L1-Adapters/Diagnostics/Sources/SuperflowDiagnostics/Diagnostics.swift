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
