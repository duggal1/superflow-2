import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import IOKit.hid
import SuperflowKernel
import SuperflowPorts

/// Real permission state, read from the frameworks that enforce it. Every check is an actual
/// probe (a TCC-backed access check or an authorization status), never a stored flag, so revoked
/// permissions surface on the next app activation.
public final class SystemPermissionGate: PermissionGate, @unchecked Sendable {
    private static let askedKey = "superflow.permissions.asked"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var observers: [UUID: AsyncStream<(Permission, PermissionStatus)>.Continuation] = [:]
    private var activationObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var asked: Set<Permission>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.askedKey) ?? []
        asked = Set(stored.compactMap(Permission.init(rawValue:)))
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    public func status(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .denied
            }
        case .accessibility:
            if AXIsProcessTrusted() { return .granted }
            return PermissionDecision.resolve(probe: .notGranted, asked: hasAsked(permission))
        case .inputMonitoring:
            // The pane and the event tap are driven by the same HID access record, so ask the
            // HID layer directly. Never treat a successfully created tap as proof of a grant:
            // `CGEvent.tapCreate` can hand back a port for a process TCC has never registered,
            // which made the app believe it was approved, skip the request, and stay absent
            // from the Input Monitoring pane.
            return InputMonitoringProbe.resolve(
                preflight: CGPreflightListenEventAccess(),
                hidGranted: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
                asked: hasAsked(permission)
            )
        case .systemAudio:
            if CGPreflightScreenCaptureAccess() { return .granted }
            return PermissionDecision.resolve(probe: .notGranted, asked: hasAsked(permission))
        }
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            // Both calls are needed. `CGRequestListenEventAccess` raises the prompt, and
            // `IOHIDRequestAccess` is the HID-level request that the Input Monitoring pane
            // reads. Either one alone can no-op for an existing record, leaving the bundle
            // missing from the list; together they guarantee TCC writes the row.
            _ = CGRequestListenEventAccess()
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .systemAudio:
            _ = CGRequestScreenCaptureAccess()
        }
        markAsked(permission)
        let current = await status(permission)
        publish(permission, current)
        return current
    }

    public func openSystemSettings(_ permission: Permission) async {
        if permission == .inputMonitoring || permission == .accessibility {
            let current = await request(permission)
            if current != .granted { await revealAppForManualGrant() }
        }
        guard let url = PermissionLinks.url(for: permission) else { return }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }

    /// Reveals the running bundle in Finder so the user can drag it onto the "+" button of a
    /// Privacy pane when macOS refuses to add it automatically.
    public func revealAppForManualGrant() async {
        _ = await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }

    public func updates() async -> AsyncStream<(Permission, PermissionStatus)> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            lock.withLock { observers[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.observers[id] = nil }
            }
            installActivationObserverIfNeeded()
            refresh()
        }
    }

    /// Re-probes everything when the app comes forward, which is exactly when a user returns from
    /// System Settings. After a manual grant in the pane, no in-app prompt fires, so this is the
    /// only signal that the status changed.
    public func refresh() {
        let continuations = lock.withLock { Array(observers.values) }
        guard !continuations.isEmpty else { return }
        Task {
            for permission in Permission.allCases {
                let current = await status(permission)
                for continuation in continuations { continuation.yield((permission, current)) }
            }
        }
    }

    // MARK: - Asked tracking

    private func hasAsked(_ permission: Permission) -> Bool {
        lock.withLock { asked.contains(permission) }
    }

    private func markAsked(_ permission: Permission) {
        let snapshot = lock.withLock { () -> [String] in
            asked.insert(permission)
            return asked.map(\.rawValue).sorted()
        }
        defaults.set(snapshot, forKey: Self.askedKey)
    }

    private func publish(_ permission: Permission, _ status: PermissionStatus) {
        let continuations = lock.withLock { Array(observers.values) }
        for continuation in continuations { continuation.yield((permission, status)) }
    }

    private func installActivationObserverIfNeeded() {
        lock.withLock {
            guard activationObserver == nil else { return }
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        }
    }
}
