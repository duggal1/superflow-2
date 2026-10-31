import Foundation

/// The frozen diagnostic vocabulary. Steps never contain transcript text.
public enum InsertionStep {
    public static let empty = "empty"
    public static let axUntrusted = "ax-untrusted"
    public static let noTarget = "no-target"
    public static let focusEditable = "focus-editable"
    public static let focusNotEditable = "focus-not-editable"
    public static let focusSecure = "focus-secure"
    public static let focusUnknown = "focus-unknown"
    public static let secureInput = "secure-input"
    public static let pbWriteFailed = "pb-write-failed"
    public static let pbWritten = "pb-written"

    // Keyboard chord.
    public static let keysPosted = "keys-posted"
    public static let keysFailed = "keys-failed"

    // Edit > Paste through the menu bar.
    public static let menuPressed = "menu-pressed"
    public static let menuDisabled = "menu-disabled"
    public static let menuNotFound = "menu-not-found"
    public static let menuFailed = "menu-failed"

    // Verification.
    public static let verified = "verified"
    public static let valueVerified = "value-verified"
    public static let notObserved = "not-observed"
    public static let unverifiable = "unverifiable"

    // Accessibility text write.
    public static let axTextVerified = "ax-text-verified"
    public static let axTextValueVerified = "ax-text-value-verified"
    public static let axTextNotObserved = "ax-text-not-observed"
    public static let axTextFailed = "ax-text-failed"

    public static let notFrontmost = "not-frontmost"

    // Older names kept so existing logs and dashboards keep parsing.
    public static let cmdvPosted = keysPosted
    public static let cmdvFailed = keysFailed
    public static let cmdvRetried = "keys-retried"
    public static let pasteNotObserved = notObserved
    public static let axVerified = axTextVerified
    public static let axValueVerified = axTextValueVerified
    public static let axNotObserved = axTextNotObserved
    public static let axSetFailed = axTextFailed

    public static func tag(_ focus: InsertionFocus) -> String {
        switch focus {
        case .editable: focusEditable
        case .notEditable: focusNotEditable
        case .secure: focusSecure
        case .unknown: focusUnknown
        }
    }

    public static func menu(_ result: MenuPasteResult) -> String {
        switch result {
        case .pressed: menuPressed
        case .disabled: menuDisabled
        case .notFound: menuNotFound
        case .failed: menuFailed
        }
    }
}

public struct InsertionReportBuilder: Sendable {
    private let started: ContinuousClock.Instant
    public private(set) var steps: [String]

    public init(started: ContinuousClock.Instant = .now, steps: [String] = []) {
        self.started = started
        self.steps = steps
    }

    public mutating func append(_ tag: String) {
        steps.append(tag)
    }

    public mutating func append(contentsOf tags: [String]) {
        steps.append(contentsOf: tags)
    }

    public func build(result: TextInsertionResult, focus: InsertionFocus, axTrusted: Bool,
                      frontmostBundleID: String? = nil, keyCode: UInt16?,
                      restoreScheduled: Bool) -> TextInsertionReport {
        let duration = started.duration(to: .now)
        let milliseconds = duration.components.seconds * 1000
            + duration.components.attoseconds / 1_000_000_000_000_000
        return TextInsertionReport(result: result, focus: focus, axTrusted: axTrusted,
                                   frontmostBundleID: frontmostBundleID, keyCode: keyCode,
                                   steps: steps, durationMs: Int(milliseconds),
                                   clipboardRestoreScheduled: restoreScheduled)
    }
}
