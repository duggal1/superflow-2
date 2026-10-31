import AppKit
import Foundation
import SuperflowKernel
import SuperflowPorts

/// `TextInserter` adapter over `TextInsertionService`: it maps the detailed
/// report onto the four existing port outcomes and implements the record-start
/// preparation hook.
public final class SystemTextInserter: TextInserter, @unchecked Sendable {
    private let service: TextInsertionService

    @MainActor
    public convenience init(pasteboard: NSPasteboard = .general) {
        self.init(service: TextInsertionService.live(pasteboard: pasteboard))
    }

    /// Test seam: inject a service built from fakes.
    public init(service: TextInsertionService) {
        self.service = service
    }

    public func insert(_ text: String, strategy: InsertionStrategy) async throws -> InsertionOutcome {
        guard !text.isEmpty else { return .pasted }
        return Self.outcome(for: await service.insert(text, options: Self.options(for: strategy)))
    }

    public func prepareForInsertion() async {
        await service.prepareFrontmost()
    }

    public func frontmostBundleID() async -> String? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    }

    /// Strategy semantics expressed as service options.
    static func options(for strategy: InsertionStrategy) -> TextInsertionOptions {
        var options = TextInsertionOptions()
        switch strategy {
        case .auto:
            break
        case .pasteboard:
            options.allowAccessibilityFallback = false
            options.preferAccessibilityForEditable = false
        case .accessibility:
            options.preferAccessibility = true
            options.allowPaste = false
        case .clipboardOnly:
            // Write the text, never post a chord, never restore over it.
            options.restoreClipboard = false
            options.allowPaste = false
            options.allowAccessibilityFallback = false
            options.preferAccessibilityForEditable = false
        }
        return options
    }

    static func outcome(for report: TextInsertionReport) -> InsertionOutcome {
        switch report.result {
        case .inserted(let method, _):
            return method == .paste ? .pasted : .accessibility
        case .notInserted(.secureField, _):
            return .blockedSecureField
        case .notInserted(.emptyText, _):
            return .pasted
        case .notInserted(.accessibilityNotTrusted, let onClipboard):
            return .permissionRequired(reason: reason(for: .accessibilityNotTrusted,
                                                       textOnClipboard: onClipboard))
        case .notInserted(let failure, let onClipboard):
            return .clipboardOnly(reason: reason(for: failure, textOnClipboard: onClipboard))
        }
    }

    private static func reason(for failure: InsertionFailure, textOnClipboard: Bool) -> String {
        let base: String
        switch failure {
        case .emptyText:
            base = "Nothing to insert."
        case .accessibilityNotTrusted:
            base = "Accessibility permission is not granted."
        case .secureField:
            base = "The focused field is secure."
        case .noEditableTarget:
            base = "No editable field is focused."
        case .targetNotFrontmost:
            base = "The target app could not be brought to the front."
        case .eventPostFailed:
            base = "The paste could not be posted."
        case .pasteNotObserved:
            base = "The paste was not observed."
        case .accessibilityFailed:
            base = "The text could not be inserted through Accessibility."
        case .clipboardWriteFailed:
            base = "The clipboard could not be written."
        case .noPasteMechanismWorked:
            base = "No paste mechanism worked."
        }
        return textOnClipboard ? "\(base) The text is on the clipboard." : base
    }
}
