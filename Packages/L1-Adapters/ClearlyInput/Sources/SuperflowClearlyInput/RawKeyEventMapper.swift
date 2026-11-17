import Foundation

/// Pure mapping from the five event-tap shapes to the recognizer's inputs.
/// Kept separate from `HotkeyService` so the device-dependent modifier bits,
/// and the "every other key cancels" rule, are testable without a tap.
public enum RawKeyEventMapper: Sendable {

    public enum EventKind: Sendable, Equatable {
        case flagsChanged
        case keyDown
        case mouseDown
    }

    /// Keycodes from the IOKit HID usage table.
    public static let rightOptionKeyCode: Int64 = 61
    public static let leftControlKeyCode: Int64 = 59
    /// Keys that must do nothing on their own (verified by tests).
    public static let leftOptionKeyCode: Int64 = 58
    public static let rightControlKeyCode: Int64 = 62

    /// Device-dependent flag bits. The aggregate `.maskAlternate` /
    /// `.maskControl` cannot distinguish sides; these can.
    public static let rightOptionDeviceBit: UInt64 = 0x40   // NX_DEVICERALTKEYMASK
    public static let leftControlDeviceBit: UInt64 = 0x01   // NX_DEVICELCTLKEYMASK

    public static func map(keyCode: Int64,
                           flags: UInt64,
                           kind: EventKind,
                           timestamp: Double) -> Clearly.RawEvent {
        switch kind {
        case .keyDown, .mouseDown:
            // Option+E, Ctrl+click and every other interaction are interference.
            return Clearly.RawEvent(.interference, at: timestamp)
        case .flagsChanged:
            if keyCode == rightOptionKeyCode {
                let down = flags & rightOptionDeviceBit != 0
                return Clearly.RawEvent(down ? .rightOptionDown : .rightOptionUp, at: timestamp)
            }
            if keyCode == leftControlKeyCode {
                let down = flags & leftControlDeviceBit != 0
                return Clearly.RawEvent(down ? .leftControlDown : .leftControlUp, at: timestamp)
            }
            // Left Option, Right Control, Shift, Command, etc. are interference
            // only while a gesture is live; in `idle` the recognizer emits nothing.
            return Clearly.RawEvent(.interference, at: timestamp)
        }
    }
}
