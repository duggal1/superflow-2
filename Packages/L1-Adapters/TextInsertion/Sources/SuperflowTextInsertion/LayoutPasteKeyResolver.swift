import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Finds the physical key that produces "v" while Command is held. This reads
/// Text Input Source and Carbon keyboard-layout APIs, which must run on the main
/// thread on current macOS.
@MainActor
public struct LayoutPasteKeyResolver: PasteKeyResolving {
    public static let fallbackKeyCode = CGKeyCode(kVK_ANSI_V)

    public init() {}

    public func pasteKeyCode() -> CGKeyCode {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return Self.fallbackKeyCode
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let commandState = UInt32((cmdKey >> 8) & 0xFF)
        let keyboardType = UInt32(LMGetKbdType())

        return data.withUnsafeBytes { buffer -> CGKeyCode in
            guard let base = buffer.baseAddress else { return Self.fallbackKeyCode }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), commandState, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars)
                if status == noErr, length == 1, chars[0] == 0x76 || chars[0] == 0x56 {
                    return CGKeyCode(code)
                }
            }
            return Self.fallbackKeyCode
        }
    }
}
