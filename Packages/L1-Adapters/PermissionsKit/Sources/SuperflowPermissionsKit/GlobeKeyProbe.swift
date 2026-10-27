import Foundation
import SuperflowPorts

/// Reads the system preference behind System Settings > Keyboard > "Press
/// Globe key to". `AppleFnUsageType` is a global-domain integer; an absent key
/// means macOS has never been told, so the probe reports `.unknown` and the
/// onboarding copy asks the user to check it rather than guessing.
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
            guard let raw = defaults.object(forKey: "AppleFnUsageType") as? Int else {
                return .unknown
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
