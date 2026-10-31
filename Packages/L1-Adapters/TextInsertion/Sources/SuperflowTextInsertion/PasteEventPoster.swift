import ApplicationServices
import Carbon.HIToolbox
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

/// Posts the full Cmd-down, V-down, V-up, Cmd-up sequence from a combined
/// session source, the shape proven clipboard managers use. The explicit
/// Command key events make the chord work in hosts that ignore a bare V with a
/// flag, and the combined source matches the stream real hardware writes.
///
/// Every event carries the L0 marker, which the hotkey tap and this package
/// both recognise, so Superflow never treats its own paste as a dictation
/// gesture.
public struct CGEventPastePoster: PasteEventPosting {
    private let postTap: CGEventTapLocation
    private let sleep: @Sendable (Duration) async -> Void

    public init(postTap: CGEventTapLocation = .cgAnnotatedSessionEventTap,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.postTap = postTap
        self.sleep = sleep
    }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func postPaste(keyCode: CGKeyCode, tap: CGEventTapLocation?) async -> Bool {
        let location = tap ?? postTap
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        // Do not let the suppression interval eat our own events.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        guard let events = Self.makePasteEvents(keyCode: keyCode, source: source) else {
            return false
        }
        events[0].post(tap: location)
        await sleep(.milliseconds(4))
        events[1].post(tap: location)
        await sleep(.milliseconds(6))
        events[2].post(tap: location)
        await sleep(.milliseconds(4))
        events[3].post(tap: location)
        return true
    }

    /// Exposed for tests: the exact shape of the four events this poster sends.
    /// Order is Command-down, V-down, V-up, Command-up.
    public static func makePasteEvents(keyCode: CGKeyCode,
                                       source: CGEventSource?) -> [CGEvent]? {
        let commandKey = CGKeyCode(kVK_Command)
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false) else {
            return nil
        }
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []
        for event in [cmdDown, vDown, vUp, cmdUp] {
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticInputMarker.value)
        }
        return [cmdDown, vDown, vUp, cmdUp]
    }

    /// Kept for tests and for callers that only need one event's shape.
    public static func makeEvent(keyCode: CGKeyCode, down: Bool,
                                 source: CGEventSource?) -> CGEvent? {
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
