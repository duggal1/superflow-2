import SuperflowKernel
import SuperflowPorts

extension SessionEngine {
    /// Retries the transcript held back by a missing Accessibility grant. Safe
    /// to call whenever the permission flips to granted: it does nothing when
    /// there is no pending text, and keeps the text if the grant is still not
    /// enough (for example the target app closed in the meantime).
    public func retryPendingInsertion() async -> InsertionOutcome? {
        guard let text = pendingInsertion else { return nil }
        do {
            let outcome = try await withDeadline(insertionDeadline, label: "insertion retry") {
                [inserter] in
                try await inserter.insert(text, strategy: .auto)
            }
            if case .permissionRequired = outcome { return outcome }
            pendingInsertion = nil
            emit(.inserted(outcome))
            return outcome
        } catch {
            return nil
        }
    }
}
