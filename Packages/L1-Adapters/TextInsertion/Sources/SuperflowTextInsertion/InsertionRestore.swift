import Carbon.HIToolbox
import Foundation

/// Cancellation token for a scheduled clipboard restore. A new insertion flushes
/// (cancels and runs immediately) any pending restore before it snapshots the
/// board, so two insertions can never restore over each other.
public struct RestoreHandle: Sendable {
    private let cancelAction: @Sendable () -> Void

    public init(cancel: @escaping @Sendable () -> Void) {
        cancelAction = cancel
    }

    public func cancel() {
        cancelAction()
    }
}

/// Lets tests await the clipboard restore instead of sleeping. Production uses a
/// detached task so the insert call returns immediately.
public protocol RestoreScheduling: Sendable {
    @discardableResult
    func schedule(after delay: Duration,
                  _ action: @escaping @Sendable () async -> Void) -> RestoreHandle
}

public struct DetachedRestoreScheduler: RestoreScheduling {
    public init() {}

    @discardableResult
    public func schedule(after delay: Duration,
                         _ action: @escaping @Sendable () async -> Void) -> RestoreHandle {
        let task = Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
        return RestoreHandle { task.cancel() }
    }
}

/// Terminal and password prompts enable Secure Input, which swallows synthetic
/// keystrokes even with Accessibility granted.
public enum SecureInput {
    public static func isActive() -> Bool {
        IsSecureEventInputEnabled()
    }
}
