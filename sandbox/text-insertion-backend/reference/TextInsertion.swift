// REFERENCE ONLY — vendored from the user-supplied TextInsertion.swift.
// It is NOT part of any SwiftPM target and is expected NOT to compile as-is.
// plan.md is normative where this file and the plan disagree.
//
// TextInsertion.swift
// Superflow — complete paste / text-insertion backend (macOS 15+, Swift 6, Apple Silicon).
//
// One file, no third-party dependencies. Not sandboxed (needs Accessibility).
//
// PUBLIC SURFACE
//   let inserter = TextInsertionService()
//   await inserter.prepare(targetPID: pid)          // call at RECORD START
//   let report = await inserter.insert(text, options: opts)   // call at SUBMIT
//   let focus  = await inserter.focusState()        // detection for the "no text field" Island card
//   PlainClipboard.copy(text)                        // Island "Copy" button
//   SyntheticInput.isSynthetic(event)                // HotkeyEngine MUST ignore events where this is true

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

// MARK: - Public types

public enum FocusState: Sendable, Equatable {
    case editable(role: String)
    case notEditable(reason: String)
    case secure
    case unknown(reason: String)
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
}

public enum InsertionOutcome: Sendable, Equatable {
    case inserted(method: InsertionMethod, verified: Bool)
    case notInserted(InsertionFailure, textOnClipboard: Bool)
}

public struct InsertionOptions: Sendable {
    public var targetPID: pid_t?
    public var restoreClipboard = true
    public var clipboardRestoreDelay: Duration = .milliseconds(500)
    public var verifyTimeout: Duration = .milliseconds(400)
    public var modifierReleaseTimeout: Duration = .milliseconds(300)
    public var copyToClipboardWhenNoTarget = false
    public var postTap: CGEventTapLocation = .cgSessionEventTap
    public init() {}
}

public struct InsertionReport: Sendable {
    public var outcome: InsertionOutcome
    public var focus: FocusState
    public var axTrusted: Bool
    public var keyCode: UInt16?
    public var steps: [String]
    public var durationMs: Int
    public var clipboardRestoreScheduled: Bool
}

// MARK: - Synthetic event marker

public enum SyntheticInput {
    /// ASCII "SFPASTE1". Stored in CGEventField.eventSourceUserData on every event we post.
    public static let marker: Int64 = 0x5346_5041_5354_4531
    public static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }
}

// MARK: - Plain clipboard (for the Island Copy button)

public enum PlainClipboard {
    @discardableResult
    public static func copy(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(text, forType: .string)
    }
}

// MARK: - Service

public actor TextInsertionService {
    private let log = Logger(subsystem: "app.superflow", category: "TextInsertion")
    private var preparedPIDs: Set<pid_t> = []
    private var chromiumCache: [pid_t: Bool] = [:]

    public init() {}

    public func prepare(targetPID pid: pid_t) {
        guard AXIsProcessTrusted(), !preparedPIDs.contains(pid) else { return }
        preparedPIDs.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    public func focusState(for pid: pid_t? = nil) -> FocusState {
        guard AXIsProcessTrusted() else { return .unknown(reason: "ax-not-trusted") }
        guard let targetPID = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return .unknown(reason: "no-frontmost-app")
        }
        return inspect(pid: targetPID).state
    }

    public func insert(_ text: String, options: InsertionOptions = InsertionOptions()) async -> InsertionReport {
        let started = ContinuousClock.now
        var steps: [String] = []
        let trusted = AXIsProcessTrusted()
        var focus: FocusState = .unknown(reason: "not-inspected")
        var usedKeyCode: UInt16?

        func finish(_ outcome: InsertionOutcome, restore: Bool = false) -> InsertionReport {
            let d = started.duration(to: .now)
            let ms = Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
            log.info("insert outcome=\(String(describing: outcome), privacy: .public) steps=\(steps.joined(separator: ","), privacy: .public) ms=\(ms)")
            return InsertionReport(outcome: outcome, focus: focus, axTrusted: trusted, keyCode: usedKeyCode,
                                   steps: steps, durationMs: ms, clipboardRestoreScheduled: restore)
        }

        guard !text.isEmpty else {
            steps.append("empty")
            return finish(.notInserted(.emptyText, textOnClipboard: false))
        }

        guard trusted else {
            steps.append("ax-untrusted")
            let ok = Self.writeTransient(text) != nil
            return finish(.notInserted(.accessibilityNotTrusted, textOnClipboard: ok))
        }

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let targetPID = options.targetPID ?? frontPID else {
            steps.append("no-target")
            return finish(.notInserted(.noEditableTarget, textOnClipboard: false))
        }
        let inspection = inspect(pid: targetPID)
        focus = inspection.state
        steps.append("focus-\(Self.tag(focus))")

        switch focus {
        case .secure:
            let ok = Self.writeTransient(text) != nil
            return finish(.notInserted(.secureField, textOnClipboard: ok))
        case .notEditable:
            var onClipboard = false
            if options.copyToClipboardWhenNoTarget { onClipboard = PlainClipboard.copy(text) }
            return finish(.notInserted(.noEditableTarget, textOnClipboard: onClipboard))
        case .editable, .unknown:
            break
        }

        guard await ensureFrontmost(targetPID) else {
            steps.append("not-frontmost")
            let ok = Self.writeTransient(text) != nil
            return finish(.notInserted(.targetNotFrontmost, textOnClipboard: ok))
        }

        var baseline: Int?
        if let element = inspection.element,
           let count = AXHelper.characterCount(element),
           AXHelper.selectionLength(element) == 0 {
            baseline = count
        }

        let pb = NSPasteboard.general
        let snapshot = options.restoreClipboard ? PasteboardSnapshot.capture(from: pb) : nil
        guard let ourChangeCount = Self.writeTransient(text) else {
            steps.append("pb-write-failed")
            return finish(.notInserted(.eventPostFailed, textOnClipboard: false))
        }
        steps.append("pb-written")

        await waitForModifiersReleased(timeout: options.modifierReleaseTimeout)

        let keyCode = await MainActor.run { KeyCodeResolver.keyCodeForPasteLetter() }
        usedKeyCode = UInt16(keyCode)

        let posted = await postPaste(keyCode: keyCode, tap: options.postTap)
        steps.append(posted ? "cmdv-posted" : "cmdv-failed")

        var inserted = false
        var verified = false
        var method: InsertionMethod = .paste

        if posted {
            if let before = baseline, let element = inspection.element {
                if await awaitCountChange(element: element, before: before, timeout: options.verifyTimeout) {
                    inserted = true; verified = true; steps.append("verified")
                } else {
                    steps.append("paste-not-observed")
                }
            } else {
                inserted = true; verified = false; steps.append("unverifiable")
            }
        }

        if !inserted, let element = inspection.element {
            let before = AXHelper.characterCount(element)
            if AXHelper.insertSelectedText(element, text) {
                if let before {
                    if await awaitCountChange(element: element, before: before, timeout: .milliseconds(250)) {
                        inserted = true; verified = true; method = .accessibility; steps.append("ax-verified")
                    } else { steps.append("ax-not-observed") }
                } else {
                    inserted = true; verified = false; method = .accessibility; steps.append("ax-unverifiable")
                }
            } else {
                steps.append("ax-set-failed")
            }
        }

        guard inserted else {
            let failure: InsertionFailure = posted ? .pasteNotObserved : .eventPostFailed
            return finish(.notInserted(failure, textOnClipboard: true))
        }

        var restoreScheduled = false
        if method == .paste, let snapshot, snapshot.isComplete {
            restoreScheduled = true
            let delay = options.clipboardRestoreDelay
            let expected = ourChangeCount
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: delay)
                let board = NSPasteboard.general
                guard board.changeCount == expected else { return }
                snapshot.restore(to: board)
            }
        }
        return finish(.inserted(method: method, verified: verified), restore: restoreScheduled)
    }

    // MARK: - Focus inspection

    private struct Inspection {
        var state: FocusState
        var element: AXUIElement?
    }

    private func inspect(pid: pid_t) -> Inspection {
        let (element, error) = AXHelper.focusedElement(pid: pid)
        guard let element else {
            switch error {
            case .apiDisabled:
                return Inspection(state: .unknown(reason: "api-disabled"), element: nil)
            case .noValue, .attributeUnsupported, .notImplemented:
                if isChromiumBased(pid: pid) { return Inspection(state: .unknown(reason: "chromium-no-ax"), element: nil) }
                return Inspection(state: .notEditable(reason: "no-focused-element"), element: nil)
            default:
                return Inspection(state: .unknown(reason: "ax-error-\(error.rawValue)"), element: nil)
            }
        }
        return Inspection(state: AXHelper.classify(element), element: element)
    }

    private func isChromiumBased(pid: pid_t) -> Bool {
        if let cached = chromiumCache[pid] { return cached }
        var result = false
        if let url = NSRunningApplication(processIdentifier: pid)?.bundleURL {
            let frameworks = url.appendingPathComponent("Contents/Frameworks", isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
            result = names.contains {
                $0.contains("Electron Framework") || $0.contains("Chrome Framework")
                    || $0.contains("Chromium Embedded Framework") || $0.contains("Edge Framework")
            }
        }
        chromiumCache[pid] = result
        return result
    }

    // MARK: - Steps

    private func ensureFrontmost(_ pid: pid_t) async -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
        await MainActor.run { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(25))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
        }
        return false
    }

    private func waitForModifiersReleased(timeout: Duration) async {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        let deadline = ContinuousClock.now + timeout
        while !CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func postPaste(keyCode: CGKeyCode, tap: CGEventTapLocation) async -> Bool {
        guard Self.postKey(keyCode: keyCode, down: true, tap: tap) else { return false }
        try? await Task.sleep(for: .milliseconds(8))
        return Self.postKey(keyCode: keyCode, down: false, tap: tap)
    }

    private func awaitCountChange(element: AXUIElement, before: Int, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(40))
            if let now = AXHelper.characterCount(element), now != before { return true }
        }
        return false
    }

    // MARK: - Static helpers

    private static func postKey(keyCode: CGKeyCode, down: Bool, tap: CGEventTapLocation) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return false }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticInput.marker)
        event.post(tap: tap)
        return true
    }

    private static func writeTransient(_ text: String) -> Int? {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { return nil }
        let marker = Data([0x31])
        for raw in ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType"] {
            _ = item.setData(marker, forType: NSPasteboard.PasteboardType(raw))
        }
        guard pb.writeObjects([item]) else { return nil }
        return pb.changeCount
    }

    private static func tag(_ f: FocusState) -> String {
        switch f {
        case .editable: "editable"
        case .notEditable: "not-editable"
        case .secure: "secure"
        case .unknown: "unknown"
        }
    }
}

// MARK: - Pasteboard snapshot

struct PasteboardSnapshot: Sendable {
    struct Entry: Sendable { let type: String; let data: Data }
    let items: [[Entry]]
    let isComplete: Bool

    static func capture(from pb: NSPasteboard, maxBytes: Int = 64 << 20) -> PasteboardSnapshot {
        var total = 0
        var complete = true
        var out: [[Entry]] = []
        for item in pb.pasteboardItems ?? [] {
            var entries: [Entry] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { complete = false; continue }
                total += data.count
                if total > maxBytes { return PasteboardSnapshot(items: [], isComplete: false) }
                entries.append(Entry(type: type.rawValue, data: data))
            }
            out.append(entries)
        }
        return PasteboardSnapshot(items: out, isComplete: complete)
    }

    func restore(to pb: NSPasteboard) {
        pb.clearContents()
        let objects: [NSPasteboardItem] = items.map { entries in
            let item = NSPasteboardItem()
            for e in entries { _ = item.setData(e.data, forType: NSPasteboard.PasteboardType(e.type)) }
            return item
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
    }
}

// MARK: - Key code resolution (main thread only)

@MainActor
enum KeyCodeResolver {
    static func keyCodeForPasteLetter() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = unsafeBitCast(raw, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return fallback }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let commandState = UInt32((cmdKey >> 8) & 0xFF)
        let keyboardType = UInt32(LMGetKbdType())
        for code in 0..<128 {
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), commandState, keyboardType,
                                        1, &deadKeys, 4, &length, &chars)
            if status == noErr, length == 1, chars[0] == 0x76 || chars[0] == 0x56 { return CGKeyCode(code) }
        }
        return fallback
    }
}

// MARK: - Accessibility helpers

enum AXHelper {
    static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let nonEditableRoles: Set<String> = [
        "AXButton", "AXStaticText", "AXImage", "AXList", "AXOutline", "AXTable", "AXRow", "AXCell", "AXColumn",
        "AXWindow", "AXApplication", "AXMenuBar", "AXMenuItem", "AXMenu", "AXToolbar", "AXRadioButton",
        "AXCheckBox", "AXPopUpButton", "AXSlider", "AXDockItem",
    ]

    static func attribute(_ element: AXUIElement, _ name: String) -> (value: CFTypeRef?, error: AXError) {
        var out: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &out)
        return (error == .success ? out : nil, error)
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name).value as? String
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    static func focusedElement(pid: pid_t) -> (element: AXUIElement?, error: AXError) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var result = attribute(app, kAXFocusedUIElementAttribute)
        if result.value == nil {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.3)
            let fallback = attribute(system, kAXFocusedUIElementAttribute)
            if let v = fallback.value, CFGetTypeID(v) == AXUIElementGetTypeID() {
                let el = unsafeBitCast(v, to: AXUIElement.self)
                var owner: pid_t = 0
                if AXUIElementGetPid(el, &owner) == .success, owner == pid { return (el, .success) }
            }
            if result.error == .success { result.error = .noValue }
        }
        guard let v = result.value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return (nil, result.error) }
        let element = unsafeBitCast(v, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.3)
        return (element, .success)
    }

    static func classify(_ element: AXUIElement) -> FocusState {
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        if subrole == "AXSecureTextField" { return .secure }
        if editableRoles.contains(role) || subrole == "AXSearchField" { return .editable(role: role) }
        if isSettable(element, kAXValueAttribute) { return .editable(role: role) }
        if attribute(element, "AXEditableAncestor").value != nil { return .editable(role: role.isEmpty ? "editable-ancestor" : role) }
        if nonEditableRoles.contains(role) { return .notEditable(reason: "role-\(role)") }
        return .unknown(reason: "role-\(role.isEmpty ? "none" : role)")
    }

    static func characterCount(_ element: AXUIElement) -> Int? {
        (attribute(element, kAXNumberOfCharactersAttribute).value as? NSNumber)?.intValue
    }

    static func selectionLength(_ element: AXUIElement) -> Int? {
        guard let v = attribute(element, kAXSelectedTextRangeAttribute).value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(v, to: AXValue.self), .cfRange, &range) else { return nil }
        return range.length
    }

    static func insertSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        guard isSettable(element, kAXSelectedTextAttribute) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }
}
