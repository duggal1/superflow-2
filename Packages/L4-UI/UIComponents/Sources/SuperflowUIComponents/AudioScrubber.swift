import Foundation
import SuperflowDesignSystem
import SwiftUI

/// The clip as a picture you can drag across to hear. Rows are frequency,
/// columns are time, and the scan column ignites the cells it passes.
///
/// Deliberately the opposite of the Island's meter: square cells, a timeline
/// read left to right, no glow. The Island says the microphone is alive; this
/// says what it actually heard.
struct SpectroScrubber: View {
    /// nil while loading or when the file cannot be decoded: the grid sits dormant.
    let clip: ClipData?
    let unavailable: Bool
    let player: ClipPlayer
    @Binding var hover: TimeInterval?
    var onTouch: () -> Void = {}

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var scrubbing = false
    @State private var reveal: CGFloat = 0

    private let rows = Spectro.bands
    private let gap: CGFloat = 2

    /// Square cells, about 4 pt, solved so the last column ends exactly on the
    /// content edge. Gaps absorb the remainder.
    private func layout(_ w: CGFloat) -> (cols: Int, cell: CGFloat) {
        let cols = max(1, Int((w + gap) / (4 + gap)))
        let raw = (w - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cell = max(1, (raw * scale).rounded(.down) / scale)
        return (cols, cell)
    }

    private var gridHeight: CGFloat {
        let cell = width > 0 ? layout(width).cell : 4
        return CGFloat(rows) * cell + CGFloat(rows - 1) * gap
    }

    var body: some View {
        // A paused clock does not tick, so a seek has to invalidate the view itself.
        let _ = player.moves
        let reveal = self.reveal
        let hoverTime = hover
        let clip = self.clip

        TimelineView(.animation(paused: player.state != .playing && !scrubbing)) { _ in
            Canvas { context, size in
                draw(&context, size, played: player.time, reveal: reveal, hoverTime: hoverTime)
            }
        }
        .frame(height: gridHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .opacity(unavailable ? 0.55 : 1)
        .overlay {
            if unavailable {
                Text("Audio unavailable")
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
            }
        }
        .contentShape(.rect)
        .gesture(scrub)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hover = clip == nil ? nil : time(at: point.x)
            case .ended: hover = nil
            }
        }
        .task(id: clip?.url) { await develop() }
        .clickable(clip != nil)
        .accessibilityElement()
        .accessibilityLabel("Recording")
        .accessibilityValue(clock(player.time))
        .accessibilityAdjustableAction { direction in
            player.seek(player.time + (direction == .increment ? 1 : -1))
        }
        .pixelAudit("SpectroScrubber")
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard clip != nil else { return }
                if !scrubbing {
                    scrubbing = true
                    onTouch()
                    player.beginScrub()
                }
                player.scrub(to: time(at: gesture.location.x))
            }
            .onEnded { _ in
                guard scrubbing else { return }
                scrubbing = false
                player.endScrub()
            }
    }

    private func time(at x: CGFloat) -> TimeInterval {
        guard width > 0, let clip else { return 0 }
        return min(max(x / width, 0), 1) * clip.duration
    }

    /// The clip develops in 14 whole steps, once. Reduce Motion starts finished.
    private func develop() async {
        guard clip != nil else { reveal = 0; return }
        guard !reduceMotion else { reveal = 1; return }
        reveal = 0
        for step in 1...14 {
            try? await Task.sleep(for: .milliseconds(34))
            if Task.isCancelled { return }
            reveal = CGFloat(step) / 14
        }
    }

    // MARK: drawing

    private func level(_ data: ClipData, column: Int, of columns: Int, band: Int) -> Int {
        let count = data.frames
        guard count > 0 else { return 0 }
        var value: UInt8 = 0
        if count >= columns {
            let low = column * count / columns
            let high = min(max(low + 1, (column + 1) * count / columns), count)
            for frame in low..<high {
                value = max(value, data.cells[frame * Spectro.bands + band])
            }
        } else {
            value = data.cells[min(count - 1, column * count / columns) * Spectro.bands + band]
        }
        return value < 40 ? 0 : value < 110 ? 1 : value < 180 ? 2 : 3
    }

    /// Deterministic 0...1 per cell, so the stepped reveal is stable.
    private func jitter(_ column: Int, _ band: Int) -> Double {
        var hash = UInt32(truncatingIfNeeded: column) &* 374761393
            &+ UInt32(truncatingIfNeeded: band) &* 668265263
            &+ 7 &* 2246822519
        hash = (hash ^ (hash >> 13)) &* 1274126177
        hash ^= hash >> 16
        return Double(hash) / Double(UInt32.max)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize,
                      played: TimeInterval, reveal: CGFloat, hoverTime: TimeInterval?) {
        let (columns, cell) = layout(size.width)
        let pitch = cell + gap
        let duration = clip?.duration ?? 0
        let progress = duration > 0 ? played / duration : 0
        let head = min(max(Int(progress * Double(columns)), 0), columns - 1)
        let ghost = hoverTime.flatMap { time in
            duration > 0 ? min(max(Int(time / duration * Double(columns)), 0), columns - 1) : nil
        }
        let eased = 1 - pow(1 - Double(reveal), 3)
        let cutoff = (eased * 14).rounded(.up) / 14

        // Unplayed cells keep the silhouette in neutral steps. Played cells use
        // the brand ramp: blue 300, blue 600, then the bright tip.
        let ahead = [Tok.control, Tok.controlHover, Tok.controlPressed]
        let played = [Ramp.blue[2], Ramp.blue[3], Ramp.blue[4]]

        for column in 0..<columns {
            let behind = head - column
            for band in 0..<rows {
                let value = clip.map { level($0, column: column, of: columns, band: band) } ?? 0
                let order = Double(column) / Double(columns) * 0.82 + jitter(column, band) * 0.18
                let lit = value > 0 && order <= cutoff
                let checker = (column + band) % 2 == 0

                var tone = Tok.well
                if lit {
                    switch behind {
                    case ..<0: tone = ahead[value - 1]
                    case 0: tone = Tok.text
                    case 1: tone = checker ? Tok.text : Ramp.blue[4]
                    case 2: tone = Ramp.blue[4]
                    case 3: tone = checker ? Ramp.blue[4] : played[value - 1]
                    default: tone = played[value - 1]
                    }
                } else if behind == 0 && duration > 0 && cutoff >= 1 {
                    // The scan guide crosses silence too, so the playhead never vanishes.
                    tone = Tok.controlPressed
                }
                if column == ghost && behind != 0 {
                    tone = lit ? Tok.text2 : Tok.control
                }

                let rect = CGRect(x: snap(CGFloat(column) * pitch),
                                  y: snap(CGFloat(rows - 1 - band) * pitch),
                                  width: cell,
                                  height: cell)
                context.fill(Path(roundedRect: rect, cornerRadius: 1, style: .continuous),
                             with: .color(tone))
            }
        }
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}

/// Floors to tenths, so 59.96 s prints 0:59.9 and never 0:60.0.
func clock(_ t: TimeInterval) -> String {
    let tenths = max(0, Int((t * 10).rounded(.down)))
    return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}
