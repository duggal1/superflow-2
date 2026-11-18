import SuperflowDesignSystem
import SwiftUI

/// The single declaration of every structural value the rebuilt Island view layer
/// uses. Nothing in a view owns a spacing, radius, colour, duration or type
/// literal: if a number is needed, it is added here with a reason.
///
/// Motion of the silhouette itself lives in the one motion engine
/// (`IslandMotion.swift`, §8.18 of DESIGN.md). These durations are the content
/// timings that ride on top of it.
public enum IslandTokens {
    // 4 pt grid.
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
    }

    public enum Radius {
        /// Concave flare where the silhouette meets the menu bar.
        public static let fillet: CGFloat = 6
        /// Convex bottom of the listening / meeting wings.
        public static let wingBottom: CGFloat = 14
        public static let chip: CGFloat = 6
        public static let cardTop: CGFloat = 12
        public static let cardBottom: CGFloat = 24
    }

    public enum Color {
        /// Opaque black so the body merges with the hardware notch. No material,
        /// no shadow, no border.
        public static let body = Tok.island
        public static let ink = Tok.text
        public static let ink2 = Tok.text2
        public static let accent = Tok.accentText
        public static let accentFill = Tok.accent
        public static let field = Tok.well
        public static let danger = Tok.statusBad
        /// The pixel waveform reads on the Island's bright-shifted one-hue ramp,
        /// never a gradient. Every step stays legible on the opaque black body
        /// in dark mode.
        public static let wave = IslandRamp.step(3)
        public static let wavePeak = IslandRamp.step(4)
        public static let waveLow = IslandRamp.step(2)
    }

    /// Roles resolve through the shared `AppType` in the `.island` scope, so the
    /// scoped Instrument Sans sizes and tracking stay in the design system.
    public enum TypeRole {
        public static let caption: AppType = .caption
        public static let body: AppType = .body
        public static let label: AppType = .label
        public static let reading: AppType = .reading
        public static let title: AppType = .title
        public static let metric: AppType = .metric
    }

    public enum Duration {
        public static let dwell: Double = 0.12
        public static let hint: Double = 2.4
        public static let rowStagger: Double = 0.035
        public static let contentIn: Double = 0.30
        public static let contentOut: Double = 0.10
    }

    public enum Size {
        public static let canvas = CGSize(width: 520, height: 360)
        public static let cardWidth: CGFloat = 480
        public static let cardPad: CGFloat = 20
        public static let band: CGFloat = 32
        public static let row: CGFloat = 40
        public static let control: CGFloat = 28
        public static let glyph: CGFloat = 14
        public static let copyWidth: CGFloat = 88
        public static let hitSlop: CGFloat = 4
        public static let restBottom: CGFloat = 12
        public static let hairline: CGFloat = 1
    }

    /// The prompt themes the Island selector offers. Keep the order stable: it
    /// is shown as a vertical list and the indices are not persisted.
    public enum Theme: String, CaseIterable, Sendable {
        case normal = "Normal"
        case codingInterview = "Coding interview"
        case sales = "Sales"
        case journal = "Journal"
        case custom = "Custom"
    }
}

/// The Island's blue ramp, raised toward vivid superflow blue.
///
/// The shared canvas ramp's two lowest dark steps are near-black navy
/// (`0x171717`, `0x172554`). On the opaque black Island body they read as dead
/// pixels, which is why the silent meter, the dotted rules and the flow rail
/// looked switched off in dark mode. This ramp keeps the SAME single hue — blue
/// 600 is the one accent — and only lifts the floor: the dimmest mark is now
/// blue 900, the readout is the accent, and the hot cell is its bright shade.
/// Five conceptual steps are kept so the existing dither logic is unchanged.
public enum IslandRamp {
    public static let steps: [Color] = [
        Ramp.blue[2], // 0  dormant — blue 900, a visible dot (was near-black)
        Ramp.blue[2], // 1  quiet   — blue 900
        Ramp.blue[3], // 2  readout — accent blue 600
        Ramp.blue[3], // 3  active  — accent blue 600
        Ramp.blue[4], // 4  head    — bright blue 400, same hue
    ]

    public static func step(_ index: Int) -> Color {
        steps[max(0, min(steps.count - 1, index))]
    }
}
