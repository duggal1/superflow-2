import Foundation
import SuperflowPorts

public enum PermissionLinks {
    /// Modern (macOS 13+) Privacy & Security pane. The legacy `com.apple.preference.security`
    /// identifier still redirects on some systems, so it is kept as a fallback rather than the
    /// primary target.
    private static let modernPane = "com.apple.settings.PrivacySecurity.extension"
    private static let legacyPane = "com.apple.preference.security"

    private static func anchor(for permission: Permission) -> String {
        switch permission {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .systemAudio: "Privacy_ScreenCapture"
        }
    }

    public static func url(for permission: Permission) -> URL? {
        URL(string: "x-apple.systempreferences:\(modernPane)?\(anchor(for: permission))")
    }

    public static func fallbackURL(for permission: Permission) -> URL? {
        URL(string: "x-apple.systempreferences:\(legacyPane)?\(anchor(for: permission))")
    }
}

public enum PermissionSummary {
    public static func granted(_ statuses: [Permission: PermissionStatus]) -> [Permission] {
        Permission.allCases.filter { statuses[$0]?.isGranted == true }
    }

    public static func missing(_ statuses: [Permission: PermissionStatus]) -> [Permission] {
        Permission.allCases.filter { statuses[$0]?.isGranted != true }
    }
}
