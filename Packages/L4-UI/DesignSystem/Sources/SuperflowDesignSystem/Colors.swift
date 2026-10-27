import AppKit
import SwiftUI

// TOKEN LIST (pass 3). Use only these; anything else is a bug.
//
// Surface ladder (luminance steps only, never a stroke)
//   bg             light #F4F4F4  dark #0A0A0A   canvas, titlebar, toolbar
//   surface        light #FFFFFF  dark #171717   cards, hovered rows
//   well           light #EDEDED  dark #0F0F0F   inset fields and tracks inside a card
//   control        light #EBEBEB  dark #1F1F1F   buttons, selected row
//   controlHover   light #E3E3E3  dark #262626
//   controlPressed light #DADADA  dark #2E2E2E
//
// Text (two levels; text.3 does not exist)
//   text           light #0A0A0A  dark #FAFAFA
//   text2          light #666666  dark #A3A3A3
//
// Text inputs on the canvas (pass 2)
//   field          light #EAEAEA  dark #101010   search, fields sitting on bg
//   fieldHover     light #E3E3E3  dark #151515
//   wash           black 5% / white 7%            hover over the sidebar blur or glass
//   washStrong     black 9% / white 12%           selected over the sidebar blur
//
// Action text on dark: one tiny step below `text` (neutral 200 against #FAFAFA).
//   textAction     light #2E2E2E  dark #E5E5E5   "Open Settings", "Get model", text links
//
// Accent: blue 600 #2563EB is the base. Hover #1D4ED8 / #3B82F6, pressed #1D4ED8.
//         Blue 800 is removed from every control. accent text #2563EB / #60A5FA,
//         soft #DBEAFE / #2563EB at 17%.
//
// Activity ramp: Ramp.blue, five steps, dark first then light (ActivityYear, ThroughputStrip).
//
// Spacing 4·8·12·16·20·24·32·48·64 (Space). Page padding 32, section gap 32,
//   card padding 20.
// Radii: capsule buttons/toggles, 16 cards, 12 nested, 8 fields and badges, 6 chips.
// Control heights: text buttons 24 (inline) or 28 (bars, cards, onboarding). 32 exists
//   only for the search field and BarIconButton.
// Type: SF Pro Regular/Medium; Exposure Italic at 28 (page/empty titles) and 40 (onboarding).
// Motion: hover 0.10 out 0.22, settle 0.28, entrance 0.78, stagger 0.07, springs snappy/smooth.

public struct RGB: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// Dynamic color that follows the system appearance. Tokens never hardcode
    /// a scheme at the call site.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}

public struct HexColor: Sendable, Equatable {
    public let light: UInt32
    public let dark: UInt32
    public let lightAlpha: Double
    public let darkAlpha: Double

    public init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.light = light
        self.dark = dark
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
    }

    public var color: Color {
        Color(light: Color(hex: light, alpha: lightAlpha),
              dark: Color(hex: dark, alpha: darkAlpha))
    }

    public var lightRGB: RGB { RGB(hex: light) }
    public var darkRGB: RGB { RGB(hex: dark) }
}

public enum Tok {
    public enum Hex {
        public static let bgLight: UInt32 = 0xF4F4F4
        public static let bgDark: UInt32 = 0x0A0A0A
        public static let surfaceLight: UInt32 = 0xFFFFFF
        public static let surfaceDark: UInt32 = 0x171717
        public static let wellLight: UInt32 = 0xEDEDED
        public static let wellDark: UInt32 = 0x0F0F0F
        public static let controlLight: UInt32 = 0xEBEBEB
        public static let controlDark: UInt32 = 0x1F1F1F
        public static let controlHoverLight: UInt32 = 0xE3E3E3
        public static let controlHoverDark: UInt32 = 0x262626
        public static let controlPressedLight: UInt32 = 0xDADADA
        public static let controlPressedDark: UInt32 = 0x2E2E2E
        public static let textLight: UInt32 = 0x0A0A0A
        public static let textDark: UInt32 = 0xFAFAFA
        public static let text2Light: UInt32 = 0x666666
        public static let text2Dark: UInt32 = 0xA3A3A3
        public static let accent: UInt32 = 0x2563EB
        public static let accentHoverLight: UInt32 = 0x1D4ED8
        public static let accentHoverDark: UInt32 = 0x3B82F6
        public static let accentPressed: UInt32 = 0x1D4ED8
        public static let accentTextLight: UInt32 = 0x2563EB
        public static let accentTextDark: UInt32 = 0x60A5FA
        public static let accentSoftLight: UInt32 = 0xDBEAFE
        public static let accentSoftDark: UInt32 = 0x2563EB
        public static let onAccent: UInt32 = 0xFFFFFF
        public static let fieldLight: UInt32 = 0xEAEAEA
        public static let fieldDark: UInt32 = 0x101010
        public static let fieldHoverLight: UInt32 = 0xE3E3E3
        public static let fieldHoverDark: UInt32 = 0x151515
    }

    // Surface ladder.
    public static let bg = HexColor(light: Hex.bgLight, dark: Hex.bgDark).color
    public static let surface = HexColor(light: Hex.surfaceLight, dark: Hex.surfaceDark).color
    public static let well = HexColor(light: Hex.wellLight, dark: Hex.wellDark).color
    public static let control = HexColor(light: Hex.controlLight, dark: Hex.controlDark).color
    public static let controlHover = HexColor(light: Hex.controlHoverLight,
                                              dark: Hex.controlHoverDark).color
    public static let controlPressed = HexColor(light: Hex.controlPressedLight,
                                                dark: Hex.controlPressedDark).color

    // Text.
    public static let text = HexColor(light: Hex.textLight, dark: Hex.textDark).color
    public static let text2 = HexColor(light: Hex.text2Light, dark: Hex.text2Dark).color

    // Action text: one tiny step below text.
    public static let textAction = Color(light: Color(hex: 0x2E2E2E), dark: Color(hex: 0xE5E5E5))

    // Text inputs that sit directly on the canvas (pass 2).
    public static let field = HexColor(light: Hex.fieldLight, dark: Hex.fieldDark).color
    public static let fieldHover = HexColor(light: Hex.fieldHoverLight, dark: Hex.fieldHoverDark).color

    // Alpha washes. Luminance tokens cannot be used over a translucent backdrop.
    public static let wash = Color(light: Color(hex: 0x000000, alpha: 0.05),
                                   dark: Color(hex: 0xFFFFFF, alpha: 0.07))
    public static let washStrong = Color(light: Color(hex: 0x000000, alpha: 0.09),
                                         dark: Color(hex: 0xFFFFFF, alpha: 0.12))

    // Accent.
    public static let accent = Color(hex: Hex.accent)
    public static let accentHover = HexColor(light: Hex.accentHoverLight,
                                             dark: Hex.accentHoverDark).color
    public static let accentPressed = Color(hex: Hex.accentPressed)
    public static let accentText = HexColor(light: Hex.accentTextLight, dark: Hex.accentTextDark).color
    public static let accentSoft = HexColor(light: Hex.accentSoftLight, dark: Hex.accentSoftDark,
                                            darkAlpha: 0.17).color
    public static let onAccent = Color(hex: Hex.onAccent)

    /// Increase Contrast is the only place a border is allowed on a surface.
    public static let contrastStroke = HexColor(light: 0xD4D4D4, dark: 0xFFFFFF,
                                                darkAlpha: 0.35).color

    /// Keycap ink. Slightly settled from pure text so the cap reads as a key,
    /// never brighter than the surface it sits on.
    public static let keycapText = HexColor(light: 0x0A0A0A, dark: 0xEDEDED).color

    /// The command-palette scrim. The one translucent black in the app.
    public static let scrim = Color(hex: 0x000000, alpha: 0.18)
}

public enum Ramp {
    public static let blue: [Color] = [
        Color(light: Color(hex: 0xE9E9E9), dark: Color(hex: 0x171717)),
        Color(light: Color(hex: 0xDBEAFE), dark: Color(hex: 0x172554)),
        Color(light: Color(hex: 0x93C5FD), dark: Color(hex: 0x1E3A8A)),
        Color(light: Color(hex: 0x2563EB), dark: Color(hex: 0x2563EB)),
        Color(light: Color(hex: 0x1E3A8A), dark: Color(hex: 0x60A5FA)),
    ]
}
