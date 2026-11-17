import Foundation

/// The three permissions the Intelligence surface depends on. This is a value
/// type so the selector and its states are headless-testable with no TCC probe.
/// Accessibility is deliberately absent: neither the hotkeys nor screen reading
/// need it, and adding it would enlarge the permission surface for no gain.
public enum IntelligencePermission: String, Sendable, CaseIterable, Identifiable {
    case microphone
    case screenRecording
    case inputMonitoring

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .microphone: "Microphone"
        case .screenRecording: "Screen Recording"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    /// Product language, not an OS error string.
    public var rationale: String {
        switch self {
        case .microphone: "Your voice is transcribed for push-to-talk."
        case .screenRecording: "Screen context is attached to an answer, with the Island excluded."
        case .inputMonitoring: "Right Option and Left Control are heard only while Superflow runs."
        }
    }

    /// The Privacy & Security pane anchor. Pure so it can be asserted in tests.
    public var privacyAnchor: String {
        switch self {
        case .microphone: "Privacy_Microphone"
        case .screenRecording: "Privacy_ScreenCapture"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
    }

    /// The exact Settings link shown by the "Fix" button. The legacy pane is
    /// retained by the app adapter as a fallback where the modern one redirects.
    public var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(privacyAnchor)")
    }
}

public enum IntelligencePermissionStatus: String, Sendable, Equatable {
    case granted, denied, notDetermined

    public var isGranted: Bool { self == .granted }

    public var label: String {
        switch self {
        case .granted: "On"
        case .denied: "Off"
        case .notDetermined: "Not set"
        }
    }
}

/// Live permission state. The real adapter probes TCC/AV on every call so a
/// revocation surfaces the next time the app becomes active; tests inject a
/// deterministic double through this seam.
public protocol IntelligencePermissionServing: Sendable {
    func statuses() async -> [IntelligencePermission: IntelligencePermissionStatus]
    func request(_ permission: IntelligencePermission) async -> IntelligencePermissionStatus
    func openSettings(_ permission: IntelligencePermission) async
}

/// Honest offline default: no probe has run, so nothing is claimed to be granted.
public struct NoopIntelligencePermissionService: IntelligencePermissionServing {
    public init() {}

    public func statuses() async -> [IntelligencePermission: IntelligencePermissionStatus] {
        Dictionary(uniqueKeysWithValues:
            IntelligencePermission.allCases.map { ($0, IntelligencePermissionStatus.notDetermined) })
    }

    public func request(_ permission: IntelligencePermission) async -> IntelligencePermissionStatus { .notDetermined }
    public func openSettings(_ permission: IntelligencePermission) async {}
}
