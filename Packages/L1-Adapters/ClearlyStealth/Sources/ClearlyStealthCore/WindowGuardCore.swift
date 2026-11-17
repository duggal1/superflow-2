/// A window whose sharing policy can be read and set. Abstract so the guard's
/// behaviour is testable with fakes; the AppKit adapter conforms `NSWindow`.
/// Main-actor isolated because AppKit windows are (matching the adapter).
@MainActor
public protocol WindowSharingControllable: AnyObject {
    var sharingMode: StealthSharingMode { get set }
}

/// Every event that can create, reveal, or re-show an app-owned window.
public enum StealthWindowEvent: Sendable, Equatable {
    case windowUpdated
    case screenParametersChanged
    case spaceChanged
    case wake
    case islandShown
}

/// Re-applies `.none` to every window the app owns. Idempotent and cheap: a
/// window already `.none` is left untouched. The invariant assertion is a
/// closure so DEBUG builds can trap while tests can observe it instead.
@MainActor
public final class WindowGuardCore {
    public typealias WindowProvider = @MainActor () -> [any WindowSharingControllable]
    public typealias InvariantAssertion = @MainActor ([any WindowSharingControllable]) -> Void

    private let windowProvider: WindowProvider
    private let invariantAssertion: InvariantAssertion?

    public init(windowProvider: @escaping WindowProvider, invariantAssertion: InvariantAssertion? = nil) {
        self.windowProvider = windowProvider
        self.invariantAssertion = invariantAssertion
    }

    /// - Returns: how many windows had to be corrected (0 once the invariant holds).
    @discardableResult
    public func enforce(on event: StealthWindowEvent? = nil) -> Int {
        let windows = windowProvider()
        var corrected = 0
        for window in windows where window.sharingMode != .none {
            window.sharingMode = .none
            corrected += 1
        }
        invariantAssertion?(windows)
        return corrected
    }
}
