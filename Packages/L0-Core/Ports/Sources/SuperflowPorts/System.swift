import Foundation
import SuperflowKernel

public struct KeyEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case fnDown
        case fnUp
        case rightCmdDown
        case rightCmdUp
        case enter
        case escape
        case otherKeyDown(UInt16)
    }
    public var kind: Kind
    public var timestampNs: UInt64
    public init(kind: Kind, timestampNs: UInt64) {
        self.kind = kind
        self.timestampNs = timestampNs
    }
}

public protocol HotkeySource: Sendable {
    var events: AsyncStream<KeyEvent> { get }
    func start() async throws
    func stop() async
    /// Installs the active tap that can swallow Enter/Escape while recording.
    func setActiveTap(_ on: Bool) async
}

public enum Permission: String, Sendable, CaseIterable, Identifiable {
    case microphone, accessibility, inputMonitoring, systemAudio
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .systemAudio: "System Audio Recording"
        }
    }
    public var rationale: String {
        switch self {
        case .microphone: "Audio never leaves this Mac."
        case .accessibility: "Superflow pastes text and swallows Escape while recording."
        case .inputMonitoring: "Superflow sees fn and right Command, never what you type."
        case .systemAudio: "Superflow captures the other participants. Video is not recorded."
        }
    }
}

public enum PermissionStatus: String, Sendable {
    case granted, denied, notDetermined
    public var isGranted: Bool { self == .granted }
}

public protocol PermissionGate: Sendable {
    func status(_ p: Permission) async -> PermissionStatus
    func request(_ p: Permission) async -> PermissionStatus
    func openSystemSettings(_ p: Permission) async
    func updates() async -> AsyncStream<(Permission, PermissionStatus)>
}

public protocol MetricsSink: Sendable {
    func record(_ name: String, valueMs: Double)
    func event(_ name: String, _ fields: [String: String])
}

/// SMAppService is the only supported launch-at-login mechanism. The controller
/// lives in the composition root so the feature layer stays platform free.
public protocol LaunchAtLoginController: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ enabled: Bool) async throws
}

public struct NoopLaunchAtLoginController: LaunchAtLoginController {
    public init() {}
    public func isEnabled() async -> Bool { false }
    public func setEnabled(_ enabled: Bool) async throws {
        guard !enabled else { throw SuperflowError.invalidState("Launch at login is unavailable.") }
    }
}

/// What macOS currently does when the Globe/Fn key is pressed alone. Onboarding
/// warns when this is not `doNothing`, because the system action steals the key
/// before Superflow's event tap sees it.
public enum GlobeKeyAction: String, Sendable, Equatable, CaseIterable {
    case doNothing
    case changeInputSource
    case emojiAndSymbols
    case dictation
    /// `AppleFnUsageType` has never been written, so macOS applies its own default for the Globe
    /// key, which is Show Emoji & Symbols. Treating that as "not checked" was wrong: it is the
    /// most common real conflict, and it is exactly the state every first-run Mac is in.
    case notConfigured
    case unknown

    public var label: String {
        switch self {
        case .doNothing: "Do Nothing"
        case .changeInputSource: "Change Input Source"
        case .emojiAndSymbols: "Show Emoji & Symbols"
        case .dictation: "Start Dictation"
        case .notConfigured: "Not set (shows Emoji & Symbols)"
        case .unknown: "Not checked"
        }
    }

    /// `.unknown` means the probe could not read the preference at all. Everything else that is
    /// not `doNothing` takes the key from Superflow, including the unset default.
    public var isConflict: Bool {
        self != .doNothing && self != .unknown
    }
}

public protocol GlobeKeyProbe: Sendable {
    func currentAction() async -> GlobeKeyAction
}

public struct UnknownGlobeKeyProbe: GlobeKeyProbe {
    public init() {}
    public func currentAction() async -> GlobeKeyAction { .unknown }
}

public struct NoopMetrics: MetricsSink {
    public init() {}
    public func record(_ name: String, valueMs: Double) {}
    public func event(_ name: String, _ fields: [String: String]) {}
}

public protocol Clock: Sendable {
    var time: any TimeSource { get }
}
