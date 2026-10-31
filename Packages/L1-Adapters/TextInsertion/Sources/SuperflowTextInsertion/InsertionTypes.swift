import CoreGraphics
import Foundation

public enum InsertionFocus: Sendable, Equatable {
    case editable(role: String)
    case notEditable(reason: String)
    case secure
    case unknown(reason: String)

    /// True only when the focused element is unambiguously a text control.
    /// Advisory only: the service still pastes into every non-secure target,
    /// because Electron and terminal hosts routinely hide the real field.
    public var isConfidentEditable: Bool {
        if case .editable = self { return true }
        return false
    }
}

public enum InsertionMethod: Sendable, Equatable {
    case paste
    case menuPaste
    case accessibility
}

public enum InsertionFailure: Sendable, Equatable {
    case emptyText
    case accessibilityNotTrusted
    case secureField
    case noEditableTarget
    case targetNotFrontmost
    case clipboardWriteFailed
    case eventPostFailed
    case pasteNotObserved
    case accessibilityFailed
    /// Every mechanism was unavailable: no chord could be posted and no menu
    /// item could be pressed. Distinct from a chord that was posted but never
    /// observed, which usually means the target ignored it.
    case noPasteMechanismWorked
}

public enum TextInsertionResult: Sendable, Equatable {
    case inserted(method: InsertionMethod, verified: Bool)
    /// `textOnClipboard == false` means the caller must offer the text itself.
    case notInserted(InsertionFailure, textOnClipboard: Bool)
}

public struct TextInsertionOptions: Sendable {
    /// nil = paste into whatever app is frontmost now (recommended).
    public var targetPID: pid_t?
    /// Only honoured with `targetPID`. When true, the target is activated and
    /// the insert fails if it cannot be brought forward. Default false: paste
    /// into the app the owner is looking at now.
    public var strictTarget: Bool
    public var restoreClipboard: Bool
    /// Last-resort window used only when the paste could not be verified. A
    /// confirmed insertion restores after `verifiedRestoreDelay` instead.
    public var clipboardRestoreDelay: Duration
    /// Short settle window after positive confirmation. The target has already
    /// read the pasteboard, so this only covers its last asynchronous hop.
    public var verifiedRestoreDelay: Duration
    public var verifyTimeout: Duration
    public var modifierReleaseTimeout: Duration
    public var allowPaste: Bool
    /// Explicit Accessibility strategy: write the text straight into the
    /// focused element instead of posting a chord.
    public var preferAccessibility: Bool
    /// Last-resort Accessibility write after every paste mechanism failed.
    public var allowAccessibilityFallback: Bool
    /// Write the text to the clipboard when nothing landed, so the Island can
    /// offer it. A failed insertion never restores the previous clipboard.
    public var writeClipboardOnFailure: Bool
    /// Flip to true if some app ignores synthetic Cmd+V. Menu paste uses no key
    /// events at all.
    public var preferMenuPaste: Bool
    /// Only the Finder needs a focused text field before a paste: a desktop
    /// paste does nothing. Every other app gets the attempt.
    public var copyToClipboardWhenNoTarget: Bool
    public var postTap: CGEventTapLocation

    public init(targetPID: pid_t? = nil,
                strictTarget: Bool = false,
                restoreClipboard: Bool = true,
                clipboardRestoreDelay: Duration = .milliseconds(600),
                verifiedRestoreDelay: Duration = .milliseconds(50),
                verifyTimeout: Duration = .milliseconds(400),
                modifierReleaseTimeout: Duration = .milliseconds(300),
                allowPaste: Bool = true,
                preferAccessibility: Bool = false,
                allowAccessibilityFallback: Bool = true,
                writeClipboardOnFailure: Bool = true,
                preferMenuPaste: Bool = false,
                copyToClipboardWhenNoTarget: Bool = false,
                postTap: CGEventTapLocation = .cgAnnotatedSessionEventTap) {
        self.targetPID = targetPID
        self.strictTarget = strictTarget
        self.restoreClipboard = restoreClipboard
        self.clipboardRestoreDelay = clipboardRestoreDelay
        self.verifiedRestoreDelay = verifiedRestoreDelay
        self.verifyTimeout = verifyTimeout
        self.modifierReleaseTimeout = modifierReleaseTimeout
        self.allowPaste = allowPaste
        self.preferAccessibility = preferAccessibility
        self.allowAccessibilityFallback = allowAccessibilityFallback
        self.writeClipboardOnFailure = writeClipboardOnFailure
        self.preferMenuPaste = preferMenuPaste
        self.copyToClipboardWhenNoTarget = copyToClipboardWhenNoTarget
        self.postTap = postTap
    }
}

public struct TextInsertionReport: Sendable {
    public var result: TextInsertionResult
    public var focus: InsertionFocus
    public var axTrusted: Bool
    public var frontmostBundleID: String?
    public var keyCode: UInt16?
    public var steps: [String]
    public var durationMs: Int
    public var clipboardRestoreScheduled: Bool

    public init(result: TextInsertionResult, focus: InsertionFocus, axTrusted: Bool,
                frontmostBundleID: String? = nil, keyCode: UInt16?, steps: [String],
                durationMs: Int, clipboardRestoreScheduled: Bool) {
        self.result = result
        self.focus = focus
        self.axTrusted = axTrusted
        self.frontmostBundleID = frontmostBundleID
        self.keyCode = keyCode
        self.steps = steps
        self.durationMs = durationMs
        self.clipboardRestoreScheduled = clipboardRestoreScheduled
    }

    /// One line, never containing transcript text.
    public var summary: String {
        "outcome=\(result) trusted=\(axTrusted) front=\(frontmostBundleID ?? "?") "
            + "focus=\(focus) steps=\(steps.joined(separator: ",")) ms=\(durationMs)"
    }
}

@MainActor
public protocol PasteKeyResolving: Sendable {
    /// The physical key that produces "v" while Command is held in the current layout.
    func pasteKeyCode() -> CGKeyCode
}
