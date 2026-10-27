import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import SuperflowKernel
import SuperflowPorts

/// Real permission state, read from the frameworks that enforce it. Every check is an actual
/// probe (an event tap or an authorization status), never a stored flag, so revoked permissions
/// surface on the next app activation.
public final class SystemPermissionGate: PermissionGate, @unchecked Sendable {
    private static let askedKey = "superflow.permissions.asked"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var observers: [UUID: AsyncStream<(Permission, PermissionStatus)>.Continuation] = [:]
    private var activationObserver: NSObjectProtocol?
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
            // Trusting the boolean alone is not enough: a stale grant can survive a re-signed
            // build while the tap no longer installs. Exercise it and prefer the tap result.
            if AXIsProcessTrusted() { return .granted }
            if Self.listenTapInstalls() { return .granted }
            return PermissionDecision.resolve(probe: .notGranted, asked: hasAsked(permission))
        case .inputMonitoring:
            // `CGPreflightListenEventAccess` can report false while the app is missing from the
            // Input Monitoring pane entirely. Creating a listen-only tap is what actually asks
            // TCC to register the app, so probe by exercising it.
            if CGPreflightListenEventAccess() { return .granted }
            if Self.listenTapInstalls() { return .granted }
            return PermissionDecision.resolve(probe: .notGranted, asked: hasAsked(permission))
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
            // Order matters. `CGRequestListenEventAccess()` only shows a prompt the first time
            // TCC sees this code identity; when a stale record already exists it returns false
            // and never adds the app to the Input Monitoring list. Creating a real listen-only
            // tap after the request is what makes TCC register the bundle, which is the only way
            // the row can appear in that pane and be toggled by hand.
            _ = CGRequestListenEventAccess()
            _ = Self.listenTapInstalls()
        case .systemAudio:
            _ = CGRequestScreenCaptureAccess()
        }
        markAsked(permission)
        let current = await status(permission)
        publish(permission, current)
        return current
    }

    public func openSystemSettings(_ permission: Permission) async {
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

    // MARK: - TCC probing

    /// Creates and immediately invalidates a listen-only event tap. A non-nil tap means TCC
    /// considers this code identity permitted for Input Monitoring; nil means it is not (and the
    /// attempt itself is what asks TCC to record the app).
    static func listenTapInstalls() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
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
        }
    }
}
