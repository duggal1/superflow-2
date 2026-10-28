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
    public static let pbWriteFailed = "pb-write-failed"
    public static let pbWritten = "pb-written"
    public static let secureInput = "secure-input"
    public static let cmdvPosted = "cmdv-posted"
    public static let cmdvFailed = "cmdv-failed"
    public static let verified = "verified"
    public static let valueVerified = "value-verified"
    public static let pasteNotObserved = "paste-not-observed"
    public static let unverifiable = "unverifiable"
    public static let axVerified = "ax-verified"
    public static let axValueVerified = "ax-value-verified"
    public static let axNotObserved = "ax-not-observed"
    public static let axSetFailed = "ax-set-failed"
    public static let notFrontmost = "not-frontmost"

    public static func tag(_ focus: InsertionFocus) -> String {
        switch focus {
        case .editable: focusEditable
        case .notEditable: focusNotEditable
        case .secure: focusSecure
        case .unknown: focusUnknown
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
                      keyCode: UInt16?, restoreScheduled: Bool) -> TextInsertionReport {
        let duration = started.duration(to: .now)
        let milliseconds = duration.components.seconds * 1000
            + duration.components.attoseconds / 1_000_000_000_000_000
        return TextInsertionReport(result: result, focus: focus, axTrusted: axTrusted,
                                   keyCode: keyCode, steps: steps,
                                   durationMs: Int(milliseconds),
                                   clipboardRestoreScheduled: restoreScheduled)
    }
}
