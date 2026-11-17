import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// The pixel vocabulary shared by the Intelligence surface hosted inside the
/// Island. It mirrors the Island's instrument-panel language: square cells on
/// whole device pixels, one blue ramp, no stroke, no gradient, no boxed glyph.
/// Kept local so FeatureIntelligence never imports another L3 feature.
enum IntelPixel {
    static let cell: CGFloat = 2
    static let gap: CGFloat = 1
    static let pitch: CGFloat = 3

    static let mark = [
        ".###.",
        "#...#",
        "#.#.#",
        "#...#",
        ".###.",
    ]
    static let send = [
        "..#..",
        "..##.",
        ".###.",
        "..#..",
        "..#..",
    ]
    static let check = [
        "......#",
        ".....#.",
        "#...#..",
        ".#.#...",
        "..#....",
    ]
    static let lock = [
        ".###.",
        "#...#",
        "#####",
        "#####",
        "#####",
    ]
    static let history = [
        "#....",
        "###..",
        "#.##.",
        "#..##",
        "#...#",
    ]
}

// MARK: - Dotted rule

/// A dotted cell rule used instead of a hairline divider.
struct IntelPixelRule: View {
    var tone: Color = Ramp.blue[1]
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            let count = max(0, Int(geo.size.width / (IntelPixel.pitch * 2)))
            Canvas { context, _ in
                for index in 0..<count {
                    let x = Pixel.snap(CGFloat(index) * IntelPixel.pitch * 2, scale)
                    context.fill(Path(CGRect(x: x, y: 0,
                                             width: Pixel.snap(IntelPixel.cell, scale),
                                             height: Pixel.snap(IntelPixel.cell, scale))),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(height: Pixel.snap(IntelPixel.cell, scale))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Heading

/// A cell glyph, a label and a dotted signal line. The Island's section
/// headers read as instrument channels, not as a generic settings form.
struct IntelPixelHeading: View {
    let glyph: [String]
    let title: String
    var tone: Color = Ramp.blue[4]
    var caption: String?

    var body: some View {
        HStack(spacing: Space.sm) {
            PixelMark(rows: glyph, cell: IntelPixel.cell, color: tone)
            Text(title).appType(.caption).foregroundStyle(Tok.text)
            if let caption {
                Text(caption).appType(.caption).foregroundStyle(Tok.text2)
            }
            IntelPixelRule(tone: Ramp.blue[2])
        }
        .frame(height: 14)
    }
}

// MARK: - Live band

/// A one-row cell band. The head walks while `active`; at rest a single centre
/// cell holds. Used wherever a spinner or a progress bar would be generic.
struct IntelPixelBand: View {
    var active: Bool = false
    var cells: Int = 20
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(paused: !active || reduce)) { timeline in
            let head = active && !reduce
                ? Int(timeline.date.timeIntervalSinceReferenceDate * 8) % cells
                : cells / 2
            Canvas { context, _ in
                for index in 0..<cells {
                    let distance = abs(index - head)
                    let tone: Color = distance == 0 ? Ramp.blue[4]
                        : distance <= 2 && active ? Ramp.blue[3]
                        : distance <= 4 && active ? Ramp.blue[2]
                        : Ramp.blue[1]
                    context.fill(Path(CGRect(x: Pixel.snap(CGFloat(index) * IntelPixel.pitch, scale),
                                             y: 0,
                                             width: Pixel.snap(IntelPixel.cell, scale),
                                             height: Pixel.snap(IntelPixel.cell, scale))),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: Pixel.snap(CGFloat(cells) * IntelPixel.pitch - IntelPixel.gap, scale),
               height: Pixel.snap(IntelPixel.cell, scale))
        .accessibilityHidden(true)
    }
}

// MARK: - Registration corners

/// L-shaped pixel arms that register a panel instead of drawing a border.
struct IntelPixelCorners: View {
    var tone: Color = Ramp.blue[2]
    var hot: Color = Ramp.blue[4]
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            let long = Pixel.snap(CGFloat(4) * IntelPixel.pitch - IntelPixel.gap, scale)
            let thick = Pixel.snap(IntelPixel.cell, scale)
            let x1 = Pixel.snap(width, scale) - thick
            let y1 = Pixel.snap(height, scale) - thick
            Canvas { context, _ in
                func cell(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                    context.fill(Path(CGRect(x: x, y: y, width: w, height: h)),
                                 with: .color(color), style: FillStyle(antialiased: false))
                }
                cell(0, 0, long, thick, hot); cell(0, 0, thick, long, hot)
                cell(x1 - long + thick, 0, long, thick, tone); cell(x1, 0, thick, long, tone)
                cell(0, y1 - long + thick, long, thick, tone); cell(0, y1 - long, thick, long, tone)
                cell(x1 - long + thick, y1, long, thick, tone); cell(x1, y1 - long, thick, long, tone)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func intelPixelFramed(tone: Color = Ramp.blue[2], hot: Color = Ramp.blue[4]) -> some View {
        overlay { IntelPixelCorners(tone: tone, hot: hot) }
    }
}
