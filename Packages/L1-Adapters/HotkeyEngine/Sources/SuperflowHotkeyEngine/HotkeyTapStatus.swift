import Foundation

/// Live state of the keyboard event taps, so the UI can be honest about the
/// difference between "presses arrive" and "we can take Fn from macOS".
public struct HotkeyTapStatus: Sendable, Equatable {
    public var passiveTapInstalled: Bool
    public var passiveTapIsFiltering: Bool
    public var fnSuppressionRequested: Bool

    public init(passiveTapInstalled: Bool, passiveTapIsFiltering: Bool,
                fnSuppressionRequested: Bool) {
        self.passiveTapInstalled = passiveTapInstalled
        self.passiveTapIsFiltering = passiveTapIsFiltering
        self.fnSuppressionRequested = fnSuppressionRequested
    }

    /// Observed presses work, but a lone Fn may still reach the system Globe
    /// action because only a filtering tap can swallow it.
    public var hasLostSuppression: Bool {
        passiveTapInstalled && fnSuppressionRequested && !passiveTapIsFiltering
    }
}
