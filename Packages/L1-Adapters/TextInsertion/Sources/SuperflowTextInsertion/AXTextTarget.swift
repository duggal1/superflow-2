import ApplicationServices
import Foundation

/// A focused editable surface. `@MainActor` because `AXUIElement` is not
/// `Sendable`; this is the only abstraction the insertion service holds.
@MainActor
public protocol InsertionTarget: AnyObject, Sendable {
    /// Number of UTF-16 units in the field, when the app exposes it.
    func characterCount() -> Int?
    /// The whole field value when the app exposes it. The primary verification
    /// signal, because it survives auto-formatting better than a count.
    func textValue() -> String?
    /// The current selection, when the app exposes it.
    func selectedRange() -> (location: Int, length: Int)?
    /// Length of the current selection, when the app exposes it.
    func selectionLength() -> Int?
    /// Replaces the selection (or inserts at the caret) through Accessibility.
    func insertSelectedText(_ text: String) -> Bool
}

/// Thin, main-actor-confined wrapper around one `AXUIElement`.
@MainActor
public final class AXTextTarget: InsertionTarget {
    private let element: AXUIElement

    public init(element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, 0.3)
    }

    public func characterCount() -> Int? {
        if let number = AXAttributes.attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber {
            return number.intValue
        }
        // Text views that do not expose a character count still expose their value.
        if let value = AXAttributes.string(element, kAXValueAttribute) {
            return value.utf16.count
        }
        return nil
    }

    public func textValue() -> String? {
        AXAttributes.string(element, kAXValueAttribute)
    }

    public func selectionLength() -> Int? {
        selectedRange()?.length
    }

    public func insertSelectedText(_ text: String) -> Bool {
        if AXAttributes.isSettable(element, kAXSelectedTextAttribute),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                        text as CFString) == .success {
            return true
        }
        // Some AppKit text views refuse `AXSelectedText` but accept a whole-value set.
        guard let value = AXAttributes.string(element, kAXValueAttribute) else { return false }
        let updated = AXValueReplacement.replacing(value: value, range: selectedRange(), with: text)
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString,
                                            updated as CFString) == .success
    }

    public func selectedRange() -> (location: Int, length: Int)? {
        let raw = AXAttributes.attribute(element, kAXSelectedTextRangeAttribute)
        guard let value = AXAttributes.axValue(raw) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return (range.location, range.length)
    }
}

/// Shared AX attribute helpers. Every call fails soft: a refused or unsupported
/// attribute is `nil`, never a crash.
enum AXAttributes {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func axValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
