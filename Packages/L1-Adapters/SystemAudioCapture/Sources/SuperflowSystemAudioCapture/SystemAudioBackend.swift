import Foundation
import SuperflowKernel
import SuperflowPorts

/// Which system-audio transport produced the samples. Exposed for diagnostics
/// and the meeting UI; nothing downstream branches on it.
public enum SystemAudioBackendKind: String, Sendable, Equatable {
    case processTap = "core-audio-tap"
    case screenCaptureKit = "screen-capture-kit"

    public var label: String {
        switch self {
        case .processTap: "Core Audio process tap"
        case .screenCaptureKit: "ScreenCaptureKit"
        }
    }
}

/// Backend selection. `automatic` tries the process tap first because it needs
/// no video permission, then falls back to ScreenCaptureKit.
public enum SystemAudioPreference: String, Sendable, CaseIterable {
    case automatic
    case processTap
    case screenCaptureKit
}

/// One capture transport behind `SystemAudioCapture`. Backends own their
/// streams, their lifecycle, and their failure events. `start` and `stop` must
/// be idempotent from the caller's point of view.
protocol SystemAudioBackend: AnyObject, Sendable {
    var kind: SystemAudioBackendKind { get }
    func start() async throws -> AudioStreams
    func stop() async
}

/// Builds the ordered backend candidates for a preference. Injected in tests
/// so every failure path is exercised without audio hardware or TCC prompts.
struct SystemAudioBackendFactory: Sendable {
    let candidates: @Sendable (SystemAudioPreference) -> [any SystemAudioBackend]

    static let live = SystemAudioBackendFactory { preference in
        switch preference {
        case .processTap:
            return [CoreAudioTapCapture()]
        case .screenCaptureKit:
            return [ScreenCaptureKitCapture()]
        case .automatic:
            if #available(macOS 14.2, *) {
                return [CoreAudioTapCapture(), ScreenCaptureKitCapture()]
            }
            return [ScreenCaptureKitCapture()]
        }
    }
}

enum SystemAudioCaptureFailure: Error, Equatable {
    case unsupportedSystem
    case permissionDenied
    case startFailed(String)

    var localizedDescription: String {
        switch self {
        case .unsupportedSystem:
            return "This macOS version cannot capture system audio."
        case .permissionDenied:
            return "System audio recording permission was denied."
        case .startFailed(let message):
            return message
        }
    }
}
