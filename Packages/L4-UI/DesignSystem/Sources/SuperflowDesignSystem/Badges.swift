import SwiftUI

public struct BadgeRamp: Sendable, Equatable {
    public let c100: UInt32
    public let c200: UInt32
    public let c600: UInt32
    public let c700: UInt32

    public init(c100: UInt32, c200: UInt32, c600: UInt32, c700: UInt32) {
        self.c100 = c100
        self.c200 = c200
        self.c600 = c600
        self.c700 = c700
    }
}

public enum BadgeVariant: String, CaseIterable, Sendable {
    case neutral, yellow, sky, blue, violet, purple, fuchsia, rose, orange, green, danger

    public static let cycle: [BadgeVariant] = [
        .blue, .green, .orange, .violet, .yellow, .purple, .sky, .fuchsia, .rose,
    ]

    public static func at(_ index: Int) -> BadgeVariant {
        cycle[((index % cycle.count) + cycle.count) % cycle.count]
    }

    public var ramp: BadgeRamp {
        switch self {
        case .neutral: return BadgeRamp(c100: 0xF5F5F5, c200: 0xF5F5F5, c600: 0x525252, c700: 0x404040)
        case .yellow: return BadgeRamp(c100: 0xFEF9C3, c200: 0xFEF08A, c600: 0xCA8A04, c700: 0xA16207)
        case .sky: return BadgeRamp(c100: 0xE0F2FE, c200: 0xBAE6FD, c600: 0x0284C7, c700: 0x0369A1)
        case .blue: return BadgeRamp(c100: 0xDBEAFE, c200: 0xBFDBFE, c600: 0x2563EB, c700: 0x1D4ED8)
        case .violet: return BadgeRamp(c100: 0xEDE9FE, c200: 0xDDD6FE, c600: 0x7C3AED, c700: 0x6D28D9)
        case .purple: return BadgeRamp(c100: 0xF3E8FF, c200: 0xE9D5FF, c600: 0x9333EA, c700: 0x7E22CE)
        case .fuchsia: return BadgeRamp(c100: 0xFAE8FF, c200: 0xF5D0FE, c600: 0xC026D3, c700: 0xA21CAF)
        case .rose: return BadgeRamp(c100: 0xFFE4E6, c200: 0xFECDD3, c600: 0xE11D48, c700: 0xBE123C)
        case .danger: return BadgeRamp(c100: 0xFFE4E6, c200: 0xFECDD3, c600: 0xE11D48, c700: 0xBE123C)
        case .orange: return BadgeRamp(c100: 0xFFEDD5, c200: 0xFED7AA, c600: 0xEA580C, c700: 0xC2410C)
        case .green: return BadgeRamp(c100: 0xDCFCE7, c200: 0xBBF7D0, c600: 0x16A34A, c700: 0x15803D)
        }
    }

    /// Tinted fill only. No edge, no inset shade, no gradient (R2).
    public func fill(dark: Bool) -> Color {
        if self == .neutral {
            return dark ? Color(hex: 0x262626) : Color(hex: 0xEBEBEB)
        }
        return dark ? Color(hex: ramp.c600, alpha: 0.17) : Color(hex: ramp.c100)
    }

    /// Light text uses c700: c600 on c100 is about 3:1 for yellow, orange and green.
    public func textColor(dark: Bool) -> Color {
        if self == .neutral {
            return dark ? Color(hex: 0xF5F5F5) : Color(hex: 0x404040)
        }
        return Color(hex: dark ? ramp.c200 : ramp.c700)
    }
}

public enum BadgeSize: String, CaseIterable, Sendable {
    case lg, md, sm

    public var fontSize: CGFloat {
        switch self {
        case .lg: 13
        case .md: 12
        case .sm: 10
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .lg: 8
        case .md: 6
        case .sm: 6
        }
    }

    public var minHeight: CGFloat {
        switch self {
        case .lg: 24
        case .md: 20
        case .sm: 18
        }
    }
}

public enum DotTone: String, CaseIterable, Sendable {
    case blue, green, orange, purple, neutral, rose

    public static let cycle: [DotTone] = [.blue, .green, .orange, .purple]

    public static func at(_ index: Int) -> DotTone {
        cycle[((index % cycle.count) + cycle.count) % cycle.count]
    }

    public var hex: UInt32 {
        switch self {
        case .blue: 0x2563EB
        case .green: 0x16A34A
        case .orange: 0xEA580C
        case .purple: 0x9333EA
        case .neutral: 0x525252
        case .rose: 0xE11D48
        }
    }

    public var color: Color { Color(hex: hex) }
}
