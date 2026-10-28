import Foundation

/// One-shot cleanup for the floating-badge Island. The old build persisted a
/// per-display origin and exposed an "Idle pill" toggle; both are gone, and the
/// values they left behind must not survive into this build.
enum StaleDefaults {
    static func removeIslandLegacy(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("island.origin") || key.hasPrefix("island.position") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "showIdlePill")
    }
}
