import CoreGraphics
import IOKit.hidsystem

/// A solo left-Control tap, never Control+C, Control+Arrow or other chords.
struct VoiceControlTap {
    private var downAt: UInt64?
    private var cancelled = false

    mutating func reset() { downAt = nil; cancelled = false }
    mutating func cancel() { if downAt != nil { cancelled = true } }

    mutating func flagsChanged(keyCode: Int64, flags: CGEventFlags, timestamp: UInt64) -> Bool {
        guard keyCode == KeyCode.leftControl else { cancel(); return false }
        let sides = UInt64(NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK)
        let down = flags.contains(.maskControl) && (
            flags.rawValue & sides == 0 || flags.rawValue & UInt64(NX_DEVICELCTLKEYMASK) != 0)
        if down {
            guard downAt == nil else { return false }
            downAt = timestamp
            cancelled = flags.contains(.maskCommand) || flags.contains(.maskShift)
                || flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn)
                || flags.rawValue & UInt64(NX_DEVICERCTLKEYMASK) != 0
            return false
        }
        defer { reset() }
        guard let downAt, !cancelled, timestamp >= downAt else { return false }
        return timestamp - downAt <= 650_000_000
    }
}
