import CoreFoundation
import Foundation

/// macOS binds the Globe/Fn key to Show Emoji & Symbols until `AppleFnUsageType` says otherwise.
/// Superflow uses Fn as its dictation key, so while it runs it puts the preference in the state
/// the Keyboard pane calls "Do Nothing" — exactly the value the user would set by hand.
///
/// Writing the preference is necessary but not always immediately sufficient: macOS can keep the
/// old Globe binding until the next login. That is why `HotkeyEngine` also swallows the lone Fn
/// press at the event-tap level whenever Accessibility allows an active tap.
///
/// The scope matches `defaults write -g`: the any-application (`.GlobalPreferences`) domain, so
/// System Settings shows the change and every app sees it.
public enum GlobeKeyOwnership {
    public static let preferenceKey = "AppleFnUsageType"
    /// The value System Settings writes for "Press Globe key to: Do Nothing".
    public static let doNothing = 0

    /// The raw global value, or nil when macOS has never been told.
    public static func rawValue() -> Int? {
        CFPreferencesCopyValue(preferenceKey as CFString,
                               kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser,
                               kCFPreferencesAnyHost) as? Int
    }

    /// Puts the Globe key in the Do Nothing state. Returns true when the stored value changed.
    /// A `false` return also covers the lazy case where macOS had never written the key, which is
    /// still a successful outcome: afterwards it is written and reads back as Do Nothing.
    @discardableResult
    public static func enforceDoNothing() -> Bool {
        let before = rawValue()
        guard before != doNothing else { return false }
        CFPreferencesSetValue(preferenceKey as CFString,
                              NSNumber(value: doNothing),
                              kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                                    kCFPreferencesCurrentUser,
                                    kCFPreferencesAnyHost)
        return rawValue() != before
    }
}
