import ApplicationServices
import CoreGraphics
import Foundation
import SuperflowKernel

public protocol PasteEventPosting: Sendable {
    var isTrusted: Bool { get }
    /// Posts the chord at `tap`; nil uses the poster's preferred location.
    func postPaste(keyCode: CGKeyCode, tap: CGEventTapLocation?) async -> Bool
}

public extension PasteEventPosting {
    func postPaste(keyCode: CGKeyCode) async -> Bool {
        await postPaste(keyCode: keyCode, tap: nil)
    }
}

/// Posts Cmd+V from a private event source with explicit Command flags, so a
/// physically held modifier can never leak into the synthetic chord. Every event
/// carries the L0 marker, which the hotkey tap and this package both recognise.
///
/// `.cgSessionEventTap` is the primary location: it is the session-level stream
/// applications actually read, and it is the location the previous working
/// implementation used. `.cghidEventTap` stays as the fallback for hosts that
/// only observe the HID stream.
public struct CGEventPastePoster: PasteEventPosting {
    private let postTap: CGEventTapLocation
    private let sleep: @Sendable (Duration) async -> Void

    public init(postTap: CGEventTapLocation = .cgSessionEventTap,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.postTap = postTap
        self.sleep = sleep
    }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func postPaste(keyCode: CGKeyCode, tap: CGEventTapLocation?) async -> Bool {
        let location = tap ?? postTap
        guard let source = CGEventSource(stateID: .privateState),
              let down = Self.makeEvent(keyCode: keyCode, down: true, source: source),
              let up = Self.makeEvent(keyCode: keyCode, down: false, source: source) else {
            return false
        }
        down.post(tap: location)
        await sleep(.milliseconds(8))
        up.post(tap: location)
        return true
    }

    /// Exposed for tests: the exact shape of the events this poster sends.
    public static func makeEvent(keyCode: CGKeyCode, down: Bool, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
            return nil
        }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticInputMarker.value)
        return event
    }
}

public enum SyntheticInput {
    public static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == SyntheticInputMarker.value
    }
}
