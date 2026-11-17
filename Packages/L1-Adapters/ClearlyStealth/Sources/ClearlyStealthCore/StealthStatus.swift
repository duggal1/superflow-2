import Foundation

/// The three honest outcomes of trying to verify hiding on this Mac.
/// `verified` is bounded by exactly what was tested (one local capture path),
/// never a claim about every capture client or share mode.
public enum StealthStatus: String, Sendable, Equatable, Codable {
    case verified
    case failed
    case unverified
}

/// Why a result is not `verified`. Kept separate from `StealthStatus` so a
/// persisted record can explain itself without a prose blob.
public enum UnverifiedReason: String, Sendable, Equatable, Codable {
    case notRun
    case screenRecordingDenied
    case unsupportedOS
    case noDisplay
    case invalidPositiveControl
    case captureFailed
    case buildChanged
}

/// What the probe measured, as ratios of magenta pixels inside each rectangle
/// (0...1). Ratios, not counts, keep the thresholds independent of display scale.
public struct ProbeMeasurement: Sendable, Equatable, Codable {
    public let controlMatchedRatio: Double
    public let islandMatchedRatio: Double

    public init(controlMatchedRatio: Double, islandMatchedRatio: Double) {
        self.controlMatchedRatio = controlMatchedRatio
        self.islandMatchedRatio = islandMatchedRatio
    }
}

/// One persisted verification result. Keyed by macOS build so a result from a
/// previous OS is never reused as proof on a new one.
public struct StealthStatusRecord: Codable, Sendable, Equatable {
    public let status: StealthStatus
    public let osBuild: String
    public let date: Date
    public let displayConfiguration: String
    public let reason: UnverifiedReason?
    public let measurement: ProbeMeasurement?

    public init(
        status: StealthStatus,
        osBuild: String,
        date: Date = Date(),
        displayConfiguration: String,
        reason: UnverifiedReason? = nil,
        measurement: ProbeMeasurement? = nil
    ) {
        self.status = status
        self.osBuild = osBuild
        self.date = date
        self.displayConfiguration = displayConfiguration
        self.reason = reason
        self.measurement = measurement
    }

    /// Returns the record only when it was produced on `build`. A missing or
    /// stale record is deliberately treated as "not verified", never as a pass.
    public static func current(_ record: StealthStatusRecord?, build: String) -> StealthStatusRecord? {
        guard let record, record.osBuild == build, record.status != .unverified else { return nil }
        return record
    }
}

/// Persistence boundary. The real store uses `UserDefaults`; tests inject an
/// in-memory store so per-build invalidation is exercised without disk state.
public protocol StealthStatusStore: AnyObject, Sendable {
    func load(build: String) -> StealthStatusRecord?
    func save(_ record: StealthStatusRecord)
}

/// Thread-safe in-memory store for tests and previews.
public final class InMemoryStealthStatusStore: StealthStatusStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: StealthStatusRecord] = [:]

    public init() {}

    public func load(build: String) -> StealthStatusRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[build]
    }

    public func save(_ record: StealthStatusRecord) {
        lock.lock()
        defer { lock.unlock() }
        records[record.osBuild] = record
    }
}

/// `UserDefaults`-backed store for the app. Records are keyed by build.
public final class UserDefaultsStealthStatusStore: StealthStatusStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let keyPrefix = "stealth.verification."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(build: String) -> StealthStatusRecord? {
        guard let data = defaults.data(forKey: Self.keyPrefix + build) else { return nil }
        return try? JSONDecoder().decode(StealthStatusRecord.self, from: data)
    }

    public func save(_ record: StealthStatusRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.keyPrefix + record.osBuild)
    }
}

/// The exact strings shown in UI. Copy is bounded: it never says "undetectable"
/// or "invisible to everything", and it always carries the build/date or the
/// reason the claim could not be made.
public struct StealthPresentation: Sendable, Equatable {
    public let title: String
    public let detail: String
    public let badge: String?

    public init(title: String, detail: String, badge: String? = nil) {
        self.title = title
        self.detail = detail
        self.badge = badge
    }
}

public enum StealthCopy {
    public static func presentation(for record: StealthStatusRecord?) -> StealthPresentation {
        guard let record else {
            return StealthPresentation(
                title: "Hiding not verified",
                detail: "Screen-capture hiding has not been checked on this Mac. Do not rely on it.",
                badge: "Hiding unverified"
            )
        }
        switch record.status {
        case .verified:
            return StealthPresentation(
                title: "Hidden from screen capture on this Mac",
                detail: "Checked on macOS \(record.osBuild). Other capture apps and share modes were not tested — see the compatibility matrix.",
                badge: nil
            )
        case .failed:
            return StealthPresentation(
                title: "Visible to screen share on this Mac",
                detail: "The Island appeared in a local capture test. Do not rely on hiding.",
                badge: "Visible in share"
            )
        case .unverified:
            let reason = record.reason.map { " (\(String(describing: $0)))" } ?? ""
            return StealthPresentation(
                title: "Hiding not verified",
                detail: "A capture check could not be completed\(reason). Do not rely on hiding.",
                badge: "Hiding unverified"
            )
        }
    }
}
