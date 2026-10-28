import CoreGraphics
import Foundation

public enum InsertionFocus: Sendable, Equatable {
    case editable(role: String)
    case notEditable(reason: String)
    case secure
    case unknown(reason: String)

    /// True only when the focused element is unambiguously a text control. AX is
    /// safe to try first for these; ambiguous containers still prefer a paste.
    public var isConfidentEditable: Bool {
        if case .editable = self { return true }
        return false
    }
}

public enum InsertionMethod: Sendable, Equatable {
    case paste
    case accessibility
}

public enum InsertionFailure: Sendable, Equatable {
    case emptyText
    case accessibilityNotTrusted
    case secureField
    case noEditableTarget
    case targetNotFrontmost
    case eventPostFailed
    case pasteNotObserved
    case accessibilityFailed
}

public enum TextInsertionResult: Sendable, Equatable {
    case inserted(method: InsertionMethod, verified: Bool)
    /// `textOnClipboard == false` means the caller must offer the text itself.
    case notInserted(InsertionFailure, textOnClipboard: Bool)
}

public struct TextInsertionOptions: Sendable {
    public var targetPID: pid_t?
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
    public var preferAccessibility: Bool
    /// Try Accessibility first for confidently editable controls. `.unknown`
    /// containers still paste first, because AX may be hiding the real field.
    public var preferAccessibilityForEditable: Bool
    public var allowAccessibilityFallback: Bool
    public var writeClipboardOnFailure: Bool
    public var postTap: CGEventTapLocation

    public init(targetPID: pid_t? = nil,
                restoreClipboard: Bool = true,
                clipboardRestoreDelay: Duration = .milliseconds(500),
                verifiedRestoreDelay: Duration = .milliseconds(50),
                verifyTimeout: Duration = .milliseconds(400),
                modifierReleaseTimeout: Duration = .milliseconds(300),
                allowPaste: Bool = true,
                preferAccessibility: Bool = false,
                preferAccessibilityForEditable: Bool = true,
                allowAccessibilityFallback: Bool = true,
                writeClipboardOnFailure: Bool = true,
                postTap: CGEventTapLocation = .cghidEventTap) {
        self.targetPID = targetPID
        self.restoreClipboard = restoreClipboard
        self.clipboardRestoreDelay = clipboardRestoreDelay
        self.verifiedRestoreDelay = verifiedRestoreDelay
        self.verifyTimeout = verifyTimeout
        self.modifierReleaseTimeout = modifierReleaseTimeout
        self.allowPaste = allowPaste
        self.preferAccessibility = preferAccessibility
        self.preferAccessibilityForEditable = preferAccessibilityForEditable
        self.allowAccessibilityFallback = allowAccessibilityFallback
        self.writeClipboardOnFailure = writeClipboardOnFailure
        self.postTap = postTap
    }
}

public struct TextInsertionReport: Sendable {
    public var result: TextInsertionResult
    public var focus: InsertionFocus
    public var axTrusted: Bool
    public var keyCode: UInt16?
    public var steps: [String]
    public var durationMs: Int
    public var clipboardRestoreScheduled: Bool

    public init(result: TextInsertionResult, focus: InsertionFocus, axTrusted: Bool,
                keyCode: UInt16?, steps: [String], durationMs: Int,
                clipboardRestoreScheduled: Bool) {
        self.result = result
        self.focus = focus
        self.axTrusted = axTrusted
        self.keyCode = keyCode
        self.steps = steps
        self.durationMs = durationMs
        self.clipboardRestoreScheduled = clipboardRestoreScheduled
    }
}

@MainActor
public protocol PasteKeyResolving: Sendable {
    /// The physical key that produces "v" while Command is held in the current layout.
    func pasteKeyCode() -> CGKeyCode
}
