import Foundation

/// Orchestrates a capture, classifies it, and persists the result keyed by
/// macOS build. The capture is injected so the whole decision + persistence
/// pipeline is testable with no Screen Recording permission and no display.
public struct StealthVerifier: Sendable {
    public let capture: any ProbeCapturing
    public let store: any StealthStatusStore
    public let osBuild: String
    public let displayConfiguration: String

    public init(
        capture: any ProbeCapturing,
        store: any StealthStatusStore,
        osBuild: String,
        displayConfiguration: String
    ) {
        self.capture = capture
        self.store = store
        self.osBuild = osBuild
        self.displayConfiguration = displayConfiguration
    }

    /// Never run while a meeting is live. Callers gate on session state.
    @discardableResult
    public func verify() async -> VerificationOutcome {
        let outcome: VerificationOutcome
        do {
            outcome = VerifierClassifier.classify(try await capture.capture())
        } catch {
            // A capture that could not complete is Unverified, never a pass.
            outcome = .unverified(.captureFailed, nil)
        }
        let record = StealthStatusRecord(
            status: outcome.status,
            osBuild: osBuild,
            date: Date(),
            displayConfiguration: displayConfiguration,
            reason: outcome.reason,
            measurement: outcome.measurement
        )
        store.save(record)
        return outcome
    }
}
