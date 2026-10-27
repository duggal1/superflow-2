import Foundation
import SuperflowPorts

/// What the OS actually reports for a permission. Only Microphone exposes a real tri-state; the
/// other three are boolean probes, so "never asked" has to be tracked by the app.
public enum PermissionProbe: Sendable, Equatable {
    case granted
    case notGranted
    case undetermined
}

/// Pure mapping from an OS probe plus "have we asked yet" to the UI-facing status.
///
/// This exists because `.denied` and `.notDetermined` need different buttons: a never-asked
/// permission must offer *Grant* (which raises the system prompt), while a denied one must offer
/// *Open Settings*. Collapsing both into `.denied` is how the Input Monitoring row ended up
/// telling users to open a pane the app had never been added to.
public enum PermissionDecision {
    public static func resolve(probe: PermissionProbe, asked: Bool) -> PermissionStatus {
        switch probe {
        case .granted:
            return .granted
        case .undetermined:
            return .notDetermined
        case .notGranted:
            return asked ? .denied : .notDetermined
        }
    }

    /// Microphone already reports `.notDetermined`, so its probe maps straight through.
    public static func microphone(authorization: MicrophoneAuthorization) -> PermissionStatus {
        switch authorization {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .notDetermined
        }
    }
}

public enum MicrophoneAuthorization: Sendable, Equatable {
    case granted
    case denied
    case undetermined
}
