import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Finds the physical key that produces "v" while Command is held. This reads
/// Text Input Source and Carbon keyboard-layout APIs, which must run on the main
/// thread on current macOS.
@MainActor
public struct LayoutPasteKeyResolver: PasteKeyResolving {
    public nonisolated static let fallbackKeyCode = CGKeyCode(kVK_ANSI_V)

    public init() {}

    /// The layout-selection policy, separated from the live TIS/UCKeyTranslate
    /// calls so it can be exercised with fixture command layers (QWERTY,
    /// Dvorak-QWERTY⌘, non-Latin) without a real keyboard layout or posted key.
    /// The first key producing `v`/`V` under Command wins; duplicates keep the
    /// lowest key code, matching AppKit's shortcut resolution.
    public static func resolveKeyCode(
        fallback: CGKeyCode = fallbackKeyCode,
        translatedScalar: (UInt16) -> UInt16?
    ) -> CGKeyCode {
        for code in 0..<128 {
            guard let scalar = translatedScalar(UInt16(code)) else { continue }
            if scalar == 0x76 || scalar == 0x56 { return CGKeyCode(code) }
        }
        return fallback
    }

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
            return Self.resolveKeyCode { code in
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), commandState, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars)
                guard status == noErr, length == 1 else { return nil }
                return chars[0]
            }
        }
    }
}
