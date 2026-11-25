import AppKit
import ApplicationServices
import Foundation
import SuperflowKernel
import SuperflowPorts

extension SystemTextInserter {
    @MainActor
    public func openVoiceShortcut(_ shortcut: VoiceOpeningShortcut) async -> Bool {
        let workspace = NSWorkspace.shared
        let bundle = shortcut == .safari ? "com.apple.Safari" : "com.google.Chrome"
        guard let app = workspace.urlForApplication(withBundleIdentifier: bundle) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        do {
            switch shortcut {
            case .whatsapp, .twitter:
                let address = shortcut == .whatsapp ? "https://web.whatsapp.com/" : "https://x.com/"
                guard let url = URL(string: address) else { return false }
                _ = try await workspace.open([url], withApplicationAt: app, configuration: configuration)
            case .chrome, .safari:
                _ = try await workspace.openApplication(at: app, configuration: configuration)
            }
            return true
        } catch { return false }
    }

    @MainActor
    public func insertAndSubmit(_ text: String, expectedBundleID: String?) async throws -> VoiceSubmission {
        guard let expectedBundleID, let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == expectedBundleID else {
            return VoiceSubmission(insertion: try await insert(text, strategy: .clipboardOnly), submitted: false)
        }
        let pid = app.processIdentifier
        guard AXIsProcessTrusted(), let composer = Self.whatsappComposer(pid: pid, bundle: expectedBundleID) else {
            return VoiceSubmission(insertion: try await insert(text, strategy: .auto), submitted: false)
        }
        let report = await service.insert(text, options: Self.options(for: .auto))
        let outcome = Self.outcome(for: report)
        guard case .inserted(_, true) = report.result,
              !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.whatsappComposer(pid: pid, bundle: expectedBundleID),
              CFEqual(current, composer),
              AXAttributes.string(current, kAXValueAttribute)?.contains(text) == true,
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        else { return VoiceSubmission(insertion: outcome, submitted: false) }
        down.postToPid(pid)
        up.postToPid(pid)
        return VoiceSubmission(insertion: outcome, submitted: true)
    }

    @MainActor
    private static func whatsappComposer(pid: pid_t, bundle: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let field = AXAttributes.element(AXAttributes.attribute(app, kAXFocusedUIElementAttribute)),
              AXAttributes.string(field, kAXSubroleAttribute) != "AXSecureTextField",
              ["AXTextArea", "AXTextField"].contains(AXAttributes.string(field, kAXRoleAttribute) ?? "")
        else { return nil }
        AXUIElementSetMessagingTimeout(field, 0.3)
        let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXPlaceholderValue"]
            .compactMap { AXAttributes.string(field, $0) }.joined(separator: " ").lowercased()
        guard label.contains("message"), !label.contains("search"), !label.contains("find") else { return nil }
        if ["net.whatsapp.whatsapp", "com.whatsapp.whatsapp"].contains(bundle.lowercased()) { return field }
        guard ["com.google.chrome", "com.apple.safari", "org.mozilla.firefox", "com.brave.browser", "com.microsoft.edgemac"]
            .contains(bundle.lowercased()) else { return nil }
        var ancestor: AXUIElement? = field
        for _ in 0..<16 {
            guard let node = ancestor else { break }
            AXUIElementSetMessagingTimeout(node, 0.3)
            if AXAttributes.string(node, kAXRoleAttribute) == "AXWebArea" {
                let value = AXAttributes.attribute(node, kAXURLAttribute)
                let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
                return url?.scheme == "https" && url?.host?.lowercased() == "web.whatsapp.com" ? field : nil
            }
            ancestor = AXAttributes.element(AXAttributes.attribute(node, kAXParentAttribute))
        }
        return nil
    }
}
