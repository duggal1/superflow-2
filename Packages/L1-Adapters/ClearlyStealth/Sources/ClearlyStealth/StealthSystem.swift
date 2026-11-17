import AppKit
import ClearlyStealthCore
import Darwin
import Foundation

/// Wires the adapter pieces together for the app.
public enum StealthSystem {
    /// The exact kernel build string (e.g. 26B123) used to key verification.
    public static func currentOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func displayConfiguration() -> String {
        NSScreen.screens.map { screen in
            let f = screen.frame
            return "\(Int(f.width))x\(Int(f.height))@\(Int(screen.backingScaleFactor))x"
        }.joined(separator: ",")
    }

    @MainActor
    public static func makeVerifier(
        store: any StealthStatusStore = UserDefaultsStealthStatusStore()
    ) -> StealthVerifier {
        StealthVerifier(
            capture: SCKitProbeCapture(),
            store: store,
            osBuild: currentOSBuild(),
            displayConfiguration: displayConfiguration()
        )
    }

    /// Copy for settings, derived only from a persisted, build-matched record.
    public static func presentation(store: any StealthStatusStore = UserDefaultsStealthStatusStore()) -> StealthPresentation {
        let record = StealthStatusRecord.current(store.load(build: currentOSBuild()), build: currentOSBuild())
        return StealthCopy.presentation(for: record)
    }
}
