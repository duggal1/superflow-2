/// Pure decision logic: turn probe pixel ratios into an honest result.
/// No capture, no AppKit, no permission — fully headless-testable.
public enum VerifierClassifier {
    /// The positive-control (`.readOnly`) window must actually be captured at
    /// least this much, otherwise the capture itself is invalid and a pass
    /// would be a false positive.
    public static let positiveControlMinimumRatio = 0.90
    /// The island probe (`.none`) must be almost entirely absent.
    public static let islandMaximumRatio = 0.01

    public static func classify(_ measurement: ProbeMeasurement) -> VerificationOutcome {
        let control = measurement.controlMatchedRatio
        let island = measurement.islandMatchedRatio

        // Out-of-range input is a broken measurement, never a pass.
        guard (0...1).contains(control), (0...1).contains(island) else {
            return .unverified(.invalidPositiveControl, measurement)
        }
        // Control missing => capture was invalid; a "pass" here would be a lie.
        guard control >= positiveControlMinimumRatio else {
            return .unverified(.invalidPositiveControl, measurement)
        }
        // Island captured => hiding failed on this Mac/build.
        guard island < islandMaximumRatio else {
            return .failed(measurement)
        }
        return .verified(measurement)
    }
}

/// The outcome of a verification attempt, carrying its measurement for audit.
public enum VerificationOutcome: Sendable, Equatable {
    case verified(ProbeMeasurement)
    case failed(ProbeMeasurement)
    case unverified(UnverifiedReason, ProbeMeasurement?)

    public var status: StealthStatus {
        switch self {
        case .verified: return .verified
        case .failed: return .failed
        case .unverified: return .unverified
        }
    }

    public var reason: UnverifiedReason? {
        switch self {
        case .unverified(let reason, _): return reason
        default: return nil
        }
    }

    public var measurement: ProbeMeasurement? {
        switch self {
        case .verified(let m), .failed(let m): return m
        case .unverified(_, let m): return m
        }
    }
}

/// Injects a capture. The real implementation (in the AppKit adapter) uses
/// `SCScreenshotManager`; tests inject fixed magenta-pixel ratios so every
/// branch — including the deliberate failure cases — is exercised headlessly.
/// Main-actor isolated because the real probe creates AppKit windows.
@MainActor
public protocol ProbeCapturing: Sendable {
    func capture() async throws -> ProbeMeasurement
}
