import Foundation

@MainActor
extension AppCoordinator {
    /// Derived only from transcript-free local metrics. Model installation is
    /// not proof that inference ran on the most recent dictation.
    func cleanupDeveloperStatus() -> String {
        guard let self, let environment = self.environment else {
            return "S1-mini status unavailable."
        }
        guard self.settings.cleanupEnabled else { return "Cleanup is disabled." }
        guard !self.settings.reflectionCleanupEnabled else {
            return "Reflection is selected; S1-mini is not being used."
        }
        let events = environment.metrics.snapshot.events
        let last = events.last { event in
            event.name == "session.cleanup.start"
                || event.name == "session.cleanup.result"
                || event.name == "session.cleanup.finish_deadline"
                || event.name.hasPrefix("cleanup.chunk.")
        }
        guard let last else { return "No S1-mini activity yet." }
        switch last.name {
        case "session.cleanup.start":
            return "S1-mini enabled; waiting for a transcript."
        case "cleanup.chunk.started":
            return "S1-mini being used."
        case "cleanup.chunk.accepted":
            return "S1-mini succeeded; transcript polished."
        case "session.cleanup.result":
            switch last.fields["state"] {
            case "cleaned": return "S1-mini used successfully."
            case "fallback": return "S1-mini failed or timed out; deterministic fallback used."
            default: return "S1-mini was not used for this dictation."
            }
        case "session.cleanup.finish_deadline":
            return "S1-mini timed out; deterministic fallback is being applied."
        case "cleanup.chunk.helper_unavailable":
            return "S1-mini failed: model is not ready."
        default:
            return "S1-mini failed or rejected output; deterministic fallback active."
        }
    }
}
