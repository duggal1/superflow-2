/// Start/stop transitions for the event taps, kept free of CoreGraphics so the
/// idempotency rules are testable without Input Monitoring permission.
///
/// `start()` may be called again after a successful `stop()`: the permission
/// can be revoked and re-granted while the app is running. A second `start()`
/// while already running, or a second `stop()` while stopped, is a no-op.
struct HotkeyLifecycle: Sendable {
    private(set) var isRunning = false

    /// Returns `true` when the caller should install the passive tap.
    mutating func beginStart() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    /// Rolls back a start whose tap installation failed.
    mutating func startFailed() {
        isRunning = false
    }

    /// Returns `true` when the caller should tear the taps down.
    mutating func beginStop() -> Bool {
        guard isRunning else { return false }
        isRunning = false
        return true
    }
}
