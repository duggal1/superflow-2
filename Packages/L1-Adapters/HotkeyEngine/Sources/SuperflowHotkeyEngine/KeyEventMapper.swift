import CoreGraphics
import Foundation
import SuperflowKernel
import SuperflowPorts

public enum KeyCode {
    public static let fn: Int64 = 0x3F
    public static let rightCommand: Int64 = 0x36
    public static let leftCommand: Int64 = 0x37
    public static let enter: Int64 = 0x24
    public static let escape: Int64 = 0x35
}

/// Pure mapping from CGEvent fields to the port's KeyEvent. Kept separate from
/// the taps so every gesture sequence can be tested without hardware.
public enum KeyEventMapper {
    public static func flagsChanged(keyCode: Int64, flags: CGEventFlags,
                                    timestampNs: UInt64) -> KeyEvent? {
        switch keyCode {
        case KeyCode.fn:
            let down = flags.contains(.maskSecondaryFn)
            return KeyEvent(kind: down ? .fnDown : .fnUp, timestampNs: timestampNs)
        case KeyCode.rightCommand:
            let down = flags.contains(.maskCommand)
            return KeyEvent(kind: down ? .rightCmdDown : .rightCmdUp, timestampNs: timestampNs)
        default:
            return nil
        }
    }

    public static func keyDown(keyCode: Int64, timestampNs: UInt64) -> KeyEvent {
        switch keyCode {
        case KeyCode.enter:
            return KeyEvent(kind: .enter, timestampNs: timestampNs)
        case KeyCode.escape:
            return KeyEvent(kind: .escape, timestampNs: timestampNs)
        default:
            return KeyEvent(kind: .otherKeyDown(UInt16(clamping: keyCode)), timestampNs: timestampNs)
        }
    }

    /// True for events the insertion backend posted itself. Both taps drop these
    /// so Superflow never reacts to its own synthetic Cmd+V or Fn flag change.
    public static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == SyntheticInputMarker.value
    }
}
