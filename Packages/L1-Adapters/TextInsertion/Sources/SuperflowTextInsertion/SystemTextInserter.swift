import AppKit
import ApplicationServices
import Carbon
import Foundation
import SuperflowKernel
import SuperflowPorts

/// Pasteboard-first insertion with an Accessibility fallback, per PLAN.md
/// section 15. The original clipboard is restored only when nothing else wrote
/// in between, and secure fields are never touched.
public final class SystemTextInserter: TextInserter, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let accessibility: AccessibilityInserting
    private let eventPoster: KeyEventPosting
    private let sleep: @Sendable (Duration) async -> Void

    public init(pasteboard: NSPasteboard = .general,
                accessibility: AccessibilityInserting = AXTextInserter(),
                eventPoster: KeyEventPosting = CGKeyEventPoster(),
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.pasteboard = pasteboard
        self.accessibility = accessibility
        self.eventPoster = eventPoster
        self.sleep = sleep
    }

    public func insert(_ text: String, strategy: InsertionStrategy) async throws -> InsertionOutcome {
        guard !text.isEmpty else { return .pasted }
        if await accessibility.isSecureField() { return .blockedSecureField }
        switch strategy {
        case .clipboardOnly:
            writeTransient(text)
            return .clipboardOnly(reason: "Copied to the clipboard.")
        case .accessibility:
            if (try? await accessibility.insert(text)) == true { return .accessibility }
            writeTransient(text)
            return .clipboardOnly(reason: "The focused app did not accept Accessibility insertion.")
        case .pasteboard, .auto:
            if try await paste(text) { return .pasted }
            if (try? await accessibility.insert(text)) == true { return .accessibility }
            writeTransient(text)
            return .clipboardOnly(reason: "Paste and Accessibility insertion both failed. The text is on the clipboard.")
        }
    }

    public func frontmostBundleID() async -> String? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    }

    private func paste(_ text: String) async throws -> Bool {
        guard eventPoster.isTrusted else { return false }
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        writeTransient(text)
        let changeCount = pasteboard.changeCount
        let posted = eventPoster.paste()
        guard posted else {
            snapshot.restore(into: pasteboard, onlyIfChangeCount: changeCount)
            return false
        }
        await sleep(.milliseconds(250))
        snapshot.restore(into: pasteboard, onlyIfChangeCount: changeCount)
        return true
    }

    private func writeTransient(_ text: String) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: .superflowTransient)
        item.setString("", forType: .superflowConcealed)
        pasteboard.writeObjects([item])
    }
}

public protocol KeyEventPosting: Sendable {
    var isTrusted: Bool { get }
    func paste() -> Bool
}

public struct CGKeyEventPoster: KeyEventPosting {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func paste() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode(), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode(), keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    /// Resolve V from the active layout instead of assuming QWERTY. Scans the
    /// virtual key codes until UCKeyTranslate produces a lowercase v.
    private func pasteKeyCode() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return 9
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode in
            guard let base = raw.baseAddress else { return 9 }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeyState, characters.count, &length, &characters)
                if status == noErr, length == 1,
                   String(utf16CodeUnits: characters, count: 1).lowercased() == "v" {
                    return CGKeyCode(code)
                }
            }
            return 9
        }
    }
}

public protocol AccessibilityInserting: Sendable {
    func isSecureField() async -> Bool
    func insert(_ text: String) async throws -> Bool
}

public struct AXTextInserter: AccessibilityInserting {
    public init() {}

    public func isSecureField() async -> Bool {
        guard let element = focusedElement() else { return false }
        let role = attribute(element, kAXRoleAttribute) as? String
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    public func insert(_ text: String) async throws -> Bool {
        guard let element = focusedElement() else { return false }
        let selected = attribute(element, kAXSelectedTextAttribute)
        if selected != nil {
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                                      text as CFTypeRef)
            if result == .success { return true }
        }
        guard let value = attribute(element, kAXValueAttribute) as? String else { return false }
        guard let range = selectedRange(element), range.location != NSNotFound else {
            let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString,
                                                      (value + text) as CFTypeRef)
            return result == .success
        }
        let ns = value as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let updated = ns.replacingCharacters(in: safeRange, with: text)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString,
                                                  updated as CFTypeRef)
        return result == .success
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}

public struct PasteboardSnapshot: @unchecked Sendable {
    private let items: [[NSPasteboard.PasteboardType: Data]]
    private let changeCount: Int

    public init(pasteboard: NSPasteboard) {
        changeCount = pasteboard.changeCount
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    public func restore(into pasteboard: NSPasteboard, onlyIfChangeCount expected: Int) {
        guard pasteboard.changeCount == expected else { return }
        pasteboard.clearContents()
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

public extension NSPasteboard.PasteboardType {
    static let superflowTransient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let superflowConcealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
}
