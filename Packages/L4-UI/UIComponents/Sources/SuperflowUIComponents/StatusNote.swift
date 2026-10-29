import SuperflowDesignSystem
import SwiftUI

/// The sidebar's engine status, drawn in pixels on the glass itself.
///
/// There is no plate. The old note sat on `Tok.surface`, which read as a black
/// hole in the sidebar at night; the fix is to delete the plate, not the pixels.
/// State is carried by a 5 × 5 brand disc of 3 pt cells and, only while the work
/// is genuinely indeterminate, a 4 pt scan rail under the label:
///
/// - **disc** — a filled pixel circle. Green when the engine is ready, blue while
///   a model is loading or the microphone is live.
/// - **ring** — the same circle, hollow, in `statusBad`. Failure is the one state
///   that carries a hue of its own, and the hole makes it unmistakable by shape.
/// - **dither** — every other cell, in `text2`. A deterministic half-power state
///   (basic cleanup) that must not pretend to be working.
/// - **fill** — while indeterminate, the disc fills outward from the centre in
///   eight steps. Reduce Motion holds the full disc.
public struct StatusNote: View {
    public let text: String
    public var level: DotLevel = .warning
    /// True only while the work genuinely has no end to show. Deterministic states
    /// must pass `false`, or the note would animate forever.
    public var working: Bool
    public var compact: Bool

    public init(text: String, level: DotLevel = .warning, working: Bool = false, compact: Bool = false) {
        self.text = text
        self.level = level
        self.working = working
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                StatusPixelMark(level: level, working: working)
                Text(text)
                    .appType(.label)
                    .foregroundStyle(Tok.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            StatusScanRail(active: working)
                .padding(.leading, 29)
        }
        .padding(.horizontal, compact ? 6 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 32 : 40, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 5 × 5 cells of 3 pt with 1 pt gaps (19 × 19), whole device pixels, never
/// antialiased. The 3/1 pair is a glyph-scale exception to the 4 pt grid and
/// lives only here.
private struct StatusPixelMark: View {
    let level: DotLevel
    let working: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let disc = [
        ".###.",
        "#####",
        "#####",
        "#####",
        ".###.",
    ]
    static let ring = [
        ".###.",
        "#...#",
        "#...#",
        "#...#",
        ".###.",
    ]
    static let cell: CGFloat = 3
    static let gap: CGFloat = 1
    static let step: TimeInterval = 0.14
    static let steps = 8

    private var width: CGFloat { CGFloat(5) * Self.cell + CGFloat(4) * Self.gap }
    private var height: CGFloat { width }

    var body: some View {
        let animating = working && !reduceMotion
        TimelineView(.animation(minimumInterval: Self.step, paused: !animating)) { context in
            let step = animating
                ? Int(context.date.timeIntervalSinceReferenceDate / Self.step) % Self.steps
                : Self.steps
            Canvas { ctx, _ in draw(&ctx, step: step, animating: animating) }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, step: Int, animating: Bool) {
        let rows = level == .error ? Self.ring : Self.disc
        let pitch = Self.cell + Self.gap

        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                let distance = hypot(Double(column) - 2, Double(row) - 2)
                let tone: Color?
                switch level {
                case .success:
                    tone = Tok.statusOK
                case .error:
                    tone = Tok.statusBad
                case .warning, .info:
                    if animating {
                        // The disc fills outward from the centre: a warm-up with
                        // a direction, not a pulse with no end.
                        tone = distance <= Double(step) * 0.45 ? Ramp.blue[4]
                            : Tok.washStrong
                    } else if level == .warning {
                        // Half-power dither. Basic cleanup is deterministic, so
                        // it must not animate.
                        tone = (column + row) % 2 == 0 ? Tok.text2 : nil
                    } else {
                        tone = Ramp.blue[4]
                    }
                }
                guard let tone else { continue }
                let rect = CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch,
                                  width: Self.cell, height: Self.cell)
                ctx.fill(Path(rect), with: .color(tone), style: FillStyle(antialiased: false))
            }
        }
    }
}

/// The animated half of the footer: 4 × 2 cells on a 6 pt pitch, with a comet head
/// and a dithered cooling trail. It is the only moving line in the sidebar, and it
/// moves only while the state is indeterminate. Reduce Motion freezes the head.
private struct StatusScanRail: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cell: CGFloat = 4
    private static let gap: CGFloat = 2
    private static let step: TimeInterval = 0.08

    var body: some View {
        let animating = active && !reduceMotion
        TimelineView(.animation(minimumInterval: Self.step, paused: !animating)) { context in
            let frame = animating
                ? Int(context.date.timeIntervalSinceReferenceDate / Self.step)
                : 0
            Canvas { ctx, size in
                draw(&ctx, size: size, frame: frame, animating: animating)
            }
        }
        .frame(height: 2)
        .opacity(active ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, frame: Int, animating: Bool) {
        let pitch = Self.cell + Self.gap
        let cols = max(1, Int((size.width + Self.gap) / pitch))
        let head = animating ? frame % (cols + 4) - 1 : 0
        let quiet = Tok.text2.opacity(0.14)

        for col in 0..<cols {
            let distance = head - col
            let tone: Color
            switch distance {
            case 0:  tone = Ramp.blue[4]
            case 1:  tone = Ramp.blue[3]
            case 2:  tone = Ramp.blue[2]
            case 3:  tone = Ramp.blue[1]
            default: tone = quiet
            }
            let rect = CGRect(x: CGFloat(col) * pitch, y: 0, width: Self.cell, height: 2)
            ctx.fill(Path(rect), with: .color(tone), style: FillStyle(antialiased: false))
        }
    }
}
