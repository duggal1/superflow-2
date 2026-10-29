import CoreGraphics
import Foundation
import SuperflowKernel
import SuperflowPorts

public enum KeyCode {
    public static let fn: Int64 = 0x3F
    public static let rightCommand: Int64 = 0x36
    public static let leftCommand: Int64 = 0x37
    public static let rightShift: Int64 = 0x3C
    public static let rightOption: Int64 = 0x3D
    public static let rightControl: Int64 = 0x3E
    public static let leftOption: Int64 = 0x3A
    public static let enter: Int64 = 0x24
    public static let escape: Int64 = 0x35
}

/// Pure mapping from CGEvent fields to the port's KeyEvent. Kept separate from
/// the taps so every gesture sequence can be tested without hardware.
public enum KeyEventMapper {
    /// Which key produced this flag change, and whether it went down. Right ⌘ stays
    /// a meeting key, so it is mapped before the dictation key is consulted.
    public static func flagsChanged(keyCode: Int64, flags: CGEventFlags,
                                    timestampNs: UInt64,
                                    dictationKey: DictationKey = .fn) -> KeyEvent? {
        if keyCode == KeyCode.rightCommand {
            let down = flags.contains(.maskCommand)
            return KeyEvent(kind: down ? .rightCmdDown : .rightCmdUp, timestampNs: timestampNs)
        }
        switch dictationKey {
        case .fn where keyCode == KeyCode.fn:
            let down = flags.contains(.maskSecondaryFn)
            return KeyEvent(kind: down ? .fnDown : .fnUp, timestampNs: timestampNs)
        case .rightOption where keyCode == KeyCode.rightOption:
            return modifier(flags.contains(.maskAlternate), timestampNs)
        case .leftOption where keyCode == KeyCode.leftOption:
            return modifier(flags.contains(.maskAlternate), timestampNs)
        case .rightShift where keyCode == KeyCode.rightShift:
            return modifier(flags.contains(.maskShift), timestampNs)
        case .rightControl where keyCode == KeyCode.rightControl:
            return modifier(flags.contains(.maskControl), timestampNs)
        default:
            return nil
        }
    }

    private static func modifier(_ down: Bool, _ timestampNs: UInt64) -> KeyEvent {
        KeyEvent(kind: down ? .fnDown : .fnUp, timestampNs: timestampNs)
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
