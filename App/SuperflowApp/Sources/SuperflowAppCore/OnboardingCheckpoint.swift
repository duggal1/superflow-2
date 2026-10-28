import Foundation

/// A launch-critical mirror of `AppSettings.onboardingComplete`.
///
/// The stored settings row is the source of truth and the only thing the gate
/// reads, but it can go missing with the database (a fresh install, a quarantined
/// or migrated file, a write that never landed). Onboarding is asked once, so the
/// completion is also kept in `UserDefaults`, which is written before the
/// database and survives it. The checkpoint only ever turns an incomplete
/// reading into a complete one, never the other way round: a deliberate reset
/// still writes `false` to the store.
enum OnboardingCheckpoint {
    private static let key = "onboarding.complete"

    static func isComplete(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func markComplete(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}
