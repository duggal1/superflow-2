import AppKit
import ClearlyStealthCore

/// Installs the real observers and drives `WindowGuardCore` over `NSApp.windows`.
/// Every app-owned window — Island, main window, any popover/tool helper — is
/// forced back to `.none` on window update, screen-parameter change, space
/// change, wake, and every Island show. No private APIs, no Accessibility.
@MainActor
public final class AppWindowGuard {
    private let core: WindowGuardCore
    private var observers: [NSObjectProtocol] = []

    public init(assertInDebug: Bool = true) {
        let assertion: WindowGuardCore.InvariantAssertion?
        if assertInDebug {
            assertion = { windows in
                #if DEBUG
                let leaked = windows.filter { $0.sharingMode != .none }
                assert(leaked.isEmpty,
                       "Stealth invariant violated: \(leaked.count) capturable app window(s)")
                #endif
            }
        } else {
            assertion = nil
        }
        core = WindowGuardCore(
            windowProvider: { NSApp.windows.map { $0 as any WindowSharingControllable } },
            invariantAssertion: assertion
        )
    }

    public func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
                _ = MainActor.assumeIsolated { self?.core.enforce(on: .windowUpdated) }
            },
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                               object: nil, queue: .main) { [weak self] _ in
                _ = MainActor.assumeIsolated { self?.core.enforce(on: .screenParametersChanged) }
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                _ = MainActor.assumeIsolated { self?.core.enforce(on: .spaceChanged) }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                _ = MainActor.assumeIsolated { self?.core.enforce(on: .wake) }
            },
        ]
        core.enforce()
    }

    /// Call whenever the Island is shown / re-seated.
    public func islandShown() {
        core.enforce(on: .islandShown)
    }

    // This guard lives for the process lifetime (one instance in the app), so
    // observers are intentionally not torn down in deinit. A nonisolated
    // deinit cannot safely touch the non-Sendable observer tokens.
}
