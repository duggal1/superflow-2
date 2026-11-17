import AppKit
import ApplicationServices
import AVFoundation
import Foundation

/// Exactly the three permissions the input layer needs. Accessibility is
/// deliberately absent: a listen-only tap does not need it, and adding it would
/// enlarge the permission surface for no gain.
public enum ClearlyPermission: String, Sendable, CaseIterable, Identifiable {
    case inputMonitoring
    case screenRecording
    case microphone

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        }
    }

    /// Why the permission is needed, in product language.
    public var rationale: String {
        switch self {
        case .inputMonitoring: "Right ⌥ and left ⌃ are heard only while Superflow runs."
        case .screenRecording: "Screen context is attached to an answer, with the Island excluded."
        case .microphone: "Your voice is transcribed for push-to-talk."
        }
    }

    /// The anchor for the Privacy & Security pane. Pure so it can be tested
    /// without opening System Settings.
    public var privacyAnchor: String {
        switch self {
        case .inputMonitoring: "Privacy_ListenEvent"
        case .screenRecording: "Privacy_ScreenCapture"
        case .microphone: "Privacy_Microphone"
        }
    }

    public func deepLink(legacy: Bool = false) -> URL? {
        let pane = legacy
            ? "com.apple.preference.security"
            : "com.apple.settings.PrivacySecurity.extension"
        return URL(string: "x-apple.systempreferences:\(pane)?\(privacyAnchor)")
    }
}

public enum ClearlyPermissionStatus: String, Sendable, Equatable {
    case notDetermined, granted, denied
}

/// Live permission state. Every check is a real TCC/AV probe, never a stored
/// flag, so a revocation surfaces the next time the app becomes active.
public final class PermissionCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [UUID: AsyncStream<(ClearlyPermission, ClearlyPermissionStatus)>.Continuation] = [:]
    private var activationObserver: NSObjectProtocol?

    public init() {}

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    public func status(_ permission: ClearlyPermission) async -> ClearlyPermissionStatus {
        switch permission {
        case .inputMonitoring:
            return CGPreflightListenEventAccess() ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            case .denied, .restricted: return .denied
            @unknown default: return .denied
            }
        }
    }

    public func request(_ permission: ClearlyPermission) async -> ClearlyPermissionStatus {
        switch permission {
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        let current = await status(permission)
        publish(permission, current)
        return current
    }

    @MainActor
    public func openSettings(_ permission: ClearlyPermission) async {
        guard let url = permission.deepLink() else { return }
        NSWorkspace.shared.open(url)
    }

    public func updates() async -> AsyncStream<(ClearlyPermission, ClearlyPermissionStatus)> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            lock.withLock { observers[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.observers[id] = nil }
            }
            installActivationObserver()
            Task { await self.refresh() }
        }
    }

    /// Re-probe all three on activation. This is the only signal after a manual
    /// change in System Settings, where no in-app prompt fires.
    public func refresh() async {
        for permission in ClearlyPermission.allCases {
            let current = await status(permission)
            publish(permission, current)
        }
    }

    private func publish(_ permission: ClearlyPermission, _ status: ClearlyPermissionStatus) {
        let continuations = lock.withLock { Array(observers.values) }
        for continuation in continuations { continuation.yield((permission, status)) }
    }

    private func installActivationObserver() {
        lock.withLock {
            guard activationObserver == nil else { return }
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { await self?.refresh() }
            }
        }
    }
}
