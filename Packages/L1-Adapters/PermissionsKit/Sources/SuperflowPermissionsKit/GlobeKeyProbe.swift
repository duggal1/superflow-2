import Foundation
import SuperflowPorts

/// Reads the system preference behind System Settings > Keyboard > "Press
/// Globe key to". `AppleFnUsageType` is a global-domain integer; an absent key means macOS has
/// never been told, and its default for the Globe key is Show Emoji & Symbols. That is a real
/// conflict, not an unknown one, so the probe reports `.notConfigured` instead of `.unknown`.
///
/// Only the suite name is stored, which keeps the type `Sendable`. The
/// non-Sendable `UserDefaults` instance is created and read inside the main
/// actor, matching the domain that owns the preference.
public struct UserDefaultsGlobeKeyProbe: GlobeKeyProbe {
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func currentAction() async -> GlobeKeyAction {
        let suite = suiteName
        return await MainActor.run {
            let defaults = suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
            guard let raw = defaults.object(forKey: GlobeKeyOwnership.preferenceKey) as? Int else {
                return .notConfigured
            }
            switch raw {
            case 0: return .doNothing
            case 1: return .changeInputSource
            case 2: return .emojiAndSymbols
            case 3: return .dictation
            default: return .unknown
            }
        }
    }
}
