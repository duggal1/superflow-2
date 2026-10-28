import AppKit
import ApplicationServices
import Foundation

@MainActor
public protocol FocusInspecting: AnyObject, Sendable {
    func inspect(pid: pid_t) -> (focus: InsertionFocus, target: (any InsertionTarget)?)
    /// Asks the app to expose its Accessibility tree (Chromium/Electron build it
    /// lazily). Idempotent per pid.
    func prepare(pid: pid_t)
}

/// Focused-element lookup for one target app. Everything here runs on the main
/// actor because `AXUIElement` must not cross an actor boundary.
@MainActor
public final class AXFocusInspector: FocusInspecting {
    private var preparedPIDs: Set<pid_t> = []
    private var chromiumCache: [pid_t: Bool] = [:]
    private let messagingTimeout: Float = 0.3

    public init() {}

    public func inspect(pid: pid_t) -> (focus: InsertionFocus, target: (any InsertionTarget)?) {
        guard AXIsProcessTrusted() else {
            return (.unknown(reason: "ax-not-trusted"), nil)
        }
        let (element, error) = focusedElement(pid: pid)
        guard let element else {
            switch error {
            case .apiDisabled:
                return (.unknown(reason: "api-disabled"), nil)
            case .noValue, .attributeUnsupported, .notImplemented:
                if isChromiumBased(pid: pid) {
                    return (.unknown(reason: "chromium-no-ax"), nil)
                }
                // Not a hard "no editable target": some apps simply hide the
                // focused element. Let the paste attempt decide.
                return (.unknown(reason: "no-focused-element"), nil)
            default:
                return (.unknown(reason: "ax-error-\(error.rawValue)"), nil)
            }
        }
        let role = AXAttributes.string(element, kAXRoleAttribute) ?? ""
        let subrole = AXAttributes.string(element, kAXSubroleAttribute) ?? ""
        let focus = AXRoleClassifier.classify(
            role: role,
            subrole: subrole,
            valueSettable: AXAttributes.isSettable(element, kAXValueAttribute),
            hasEditableAncestor: AXAttributes.attribute(element, "AXEditableAncestor") != nil)
        return (focus, AXTextTarget(element: element))
    }

    public func prepare(pid: pid_t) {
        guard AXIsProcessTrusted(), !preparedPIDs.contains(pid) else { return }
        preparedPIDs.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        // `AXManualAccessibility` turns on the Chromium/Electron AX tree without
        // the window-animation side effects of `AXEnhancedUserInterface`.
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    public func isChromiumBased(pid: pid_t) -> Bool {
        if let cached = chromiumCache[pid] { return cached }
        var result = false
        if let url = NSRunningApplication(processIdentifier: pid)?.bundleURL {
            let frameworks = url.appendingPathComponent("Contents/Frameworks", isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
            result = ChromiumDetector.isChromium(frameworkNames: names)
        }
        chromiumCache[pid] = result
        return result
    }

    private func focusedElement(pid: pid_t) -> (element: AXUIElement?, error: AXError) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var value: CFTypeRef?
        let appError = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        if let element = AXAttributes.element(value) {
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            return (element, .success)
        }

        // System-wide fallback, but only when the element really belongs to the
        // requested app: otherwise we would paste into whatever has focus instead.
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var systemValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &systemValue) == .success,
           let element = AXAttributes.element(systemValue) {
            var owner: pid_t = 0
            if AXUIElementGetPid(element, &owner) == .success, owner == pid {
                AXUIElementSetMessagingTimeout(element, messagingTimeout)
                return (element, .success)
            }
        }
        return (nil, appError == .success ? .noValue : appError)
    }
}

/// Pure framework-name check so the Chromium heuristic is testable without an app.
public enum ChromiumDetector {
    static let signatures = [
        "Electron Framework", "Chrome Framework", "Chromium Embedded Framework", "Edge Framework",
    ]

    public static func isChromium(frameworkNames names: [String]) -> Bool {
        names.contains { name in signatures.contains { name.contains($0) } }
    }
}
