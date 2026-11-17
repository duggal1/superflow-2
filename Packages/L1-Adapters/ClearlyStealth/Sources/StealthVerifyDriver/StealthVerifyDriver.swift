import Foundation
import ClearlyStealth
import ClearlyStealthCore

/// Headless verification driver for R17.
///
/// Runs the REAL `StealthVerifier` with the REAL `SCKitProbeCapture` (two
/// magenta probe rectangles, one `.none` and one `.readOnly` positive control,
/// captured through ScreenCaptureKit with no window exclusions) and prints the
/// honest `Verified` / `Failed` / `Unverified` result as JSON.
///
/// The probe must be drawn on the display to be captured, so two 32x32
/// rectangles appear briefly; the app itself is never launched or activated,
/// no cursor is moved and no global input event is posted.
///
/// Usage: StealthVerifyDriver [--force-capturable]
/// Exit:  0 = verified, 1 = failed, 2 = unverified, 3 = bad args.
@main
struct StealthVerifyDriver {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.allSatisfy({ $0 == "--force-capturable" }) else {
            FileHandle.standardError.write(
                "usage: StealthVerifyDriver [--force-capturable]\n".data(using: .utf8)!)
            exit(3)
        }
        let forceCapturable = args.contains("--force-capturable")
        if forceCapturable {
            FileHandle.standardError.write(
                "FORCE-CAPTURABLE: Island probe is .readOnly; a working verifier MUST report Failed.\n"
                    .data(using: .utf8)!)
        }
        let code = await run(forceCapturable: forceCapturable)
        exit(code)
    }

    @MainActor
    static func run(forceCapturable: Bool) async -> Int32 {
        let store = InMemoryStealthStatusStore()
        let build = StealthSystem.currentOSBuild()
        let verifier = StealthVerifier(
            capture: SCKitProbeCapture(forceIslandCapturable: forceCapturable),
            store: store,
            osBuild: build,
            displayConfiguration: StealthSystem.displayConfiguration()
        )
        let outcome = await verifier.verify()

        // The exact app path: read the build-matched record and derive honest copy.
        let record = store.load(build: build)
        let presentation = StealthSystem.presentation(store: store)
        let isCurrentProof = StealthStatusRecord.current(record, build: build) != nil

        var payload: [String: Any] = [
            "status": outcome.status.rawValue,
            "forceCapturable": forceCapturable,
            "osBuild": build,
            "reason": outcome.reason?.rawValue ?? NSNull(),
            "isCurrentProof": isCurrentProof,
            "controlMinimum": VerifierClassifier.positiveControlMinimumRatio,
            "islandMaximum": VerifierClassifier.islandMaximumRatio,
            "copy": [
                "title": presentation.title,
                "detail": presentation.detail,
                "badge": presentation.badge.map { $0 as Any } ?? NSNull(),
            ] as [String: Any],
        ]
        if let measurement = outcome.measurement {
            payload["measurement"] = [
                "controlMatchedRatio": measurement.controlMatchedRatio,
                "islandMatchedRatio": measurement.islandMatchedRatio,
            ]
        } else {
            payload["measurement"] = NSNull()
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                  options: [.sortedKeys, .prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            FileHandle.standardOutput.write(Data((json + "\n").utf8))
        }

        switch outcome.status {
        case .verified: return 0
        case .failed: return 1
        case .unverified: return 2
        }
    }
}
