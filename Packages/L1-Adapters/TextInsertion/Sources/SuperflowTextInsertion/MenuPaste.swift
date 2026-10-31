import ApplicationServices
import Foundation

public enum MenuPasteResult: Sendable, Equatable {
    case pressed
    case disabled
    case notFound
    case failed
}

/// Second paste mechanism. Pressing Edit > Paste through Accessibility needs no
/// key events at all, so it works in hosts that ignore synthetic chords and in
/// keyboard layouts where Cmd+V is not a paste shortcut.
public protocol MenuPasting: Sendable {
    func pressPaste(pid: pid_t) -> MenuPasteResult
}

/// Finds the menu item whose shortcut is plain Cmd+V and presses it. Matching
/// on the shortcut rather than the title keeps this language independent.
public struct AXMenuPaste: MenuPasting {
    public init() {}

    public func pressPaste(pid: pid_t) -> MenuPasteResult {
        Self.press(pid: pid)
    }

    public static func press(pid: pid_t) -> MenuPasteResult {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let rawBar = AXAttributes.attribute(app, kAXMenuBarAttribute),
              let bar = AXAttributes.element(rawBar),
              let barItems = AXAttributes.attribute(bar, kAXChildrenAttribute) as? [AXUIElement] else {
            return .notFound
        }

        // The first item is the Apple menu; Edit is searched first for speed.
        let candidates = Array(barItems.dropFirst())
        let edit = candidates.filter { AXAttributes.string($0, kAXTitleAttribute) == "Edit" }
        let others = candidates.filter { AXAttributes.string($0, kAXTitleAttribute) != "Edit" }
        for group in [edit, others] where !group.isEmpty {
            for barItem in group {
                guard let menus = AXAttributes.attribute(barItem, kAXChildrenAttribute) as? [AXUIElement],
                      let menu = menus.first,
                      let items = AXAttributes.attribute(menu, kAXChildrenAttribute) as? [AXUIElement] else {
                    continue
                }
                for item in items {
                    guard AXAttributes.string(item, kAXMenuItemCmdCharAttribute)?.uppercased() == "V" else {
                        continue
                    }
                    // Missing attribute means Command-only, the common case.
                    let modifiers = (AXAttributes.attribute(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
                    guard modifiers == 0 else { continue }
                    let enabled = (AXAttributes.attribute(item, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true
                    if !enabled { return .disabled }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                        ? .pressed : .failed
                }
            }
        }
        return .notFound
    }
}
