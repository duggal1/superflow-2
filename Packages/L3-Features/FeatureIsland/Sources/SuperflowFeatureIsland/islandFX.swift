import SuperflowDesignSystem
import SuperflowIcons
import SwiftUI

/// Cancel. The meter freezes on its last frame, then comes apart: outer cells fall one row and dim, then go,
/// the core follows, and what remains is a dotted line. 14 whole steps over 0.52 s. Plays once.
struct PixelDissolve: View {
    let trail: [Float]
    @State private var born = Date()
    @State private var done = false
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let trail = trail, reduce = reduce
        let grid = IslandPixelGrid(scale: scale)
        TimelineView(.animation(paused: done)) { tl in
            let p = reduce ? 1 : min(1, tl.date.timeIntervalSince(born) / 0.52)
            let step = Int((p * 14).rounded(.down))
            let _ = { if p >= 1 && !done { Task { @MainActor in done = true } } }()
            Canvas { ctx, _ in
                let cols = 11, mid = 3
                func fill(_ c: Int, _ r: Int, _ tone: Color) {
                    ctx.fill(Path(grid.rect(CGRect(x: CGFloat(c) * 3, y: CGFloat(r) * 3, width: 2, height: 2))),
                             with: .color(tone), style: FillStyle(antialiased: false))
                }
                for c in 0..<cols {
                    let d = abs(c - cols / 2)
                    let h = islandHalf(trail.isEmpty ? 0 : trail[min(d, trail.count - 1)], max: 3)
                    if h > 0 {
                        for r in (mid - h)...(mid + h) {
                            let tip = abs(r - mid) == h
                            let die = Int((tip ? 0 : 5.0) + hash(c, r) * 6)                 // tips first, core last, scattered
                            if step < die { fill(c, r, tip ? Ramp.blue[4] : Ramp.blue[3]) }
                            else if step < die + 2 { fill(c, r + 1, Ramp.blue[2]) }         // falls one row, dims, goes
                        }
                    }
                    if h == 0 || step >= 12 { fill(c, mid, step >= 13 ? Ramp.blue[1] : Ramp.blue[2]) }
                }
            }
        }
        .frame(width: grid.length(32), height: grid.length(20)).accessibilityHidden(true)
    }

    private func hash(_ i: Int, _ j: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: i) &* 374761393 &+ UInt32(truncatingIfNeeded: j) &* 668265263
        h = (h ^ (h >> 13)) &* 1274126177; h ^= h >> 16
        return Double(h) / Double(UInt32.max)
    }
}

/// Submitting. One pulse of the meter's own shape sweeps left to right with a white head and a dithered wake.
/// 1.1 s per pass, display-rate. This replaces the three-cell wait mark and stays the one looping mark.
struct PixelSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.displayScale) private var scale
    var body: some View {
        TimelineView(.animation(paused: reduce)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2)
                / 1.2 * 2 * Double.pi
            let progress = reduce ? 0.5 : (1 - cos(phase)) / 2
            let direction: CGFloat = reduce || sin(phase) >= 0 ? 1 : -1
            let scale = scale
            Canvas { context, _ in
                func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
                func cell(_ x: CGFloat, _ y: CGFloat, _ tone: Color) {
                    context.fill(Path(CGRect(x: snap(x), y: snap(y), width: 2, height: 2)),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
                for column in 0..<11 { cell(CGFloat(column) * 3, 3, Ramp.blue[1]) }
                let head = snap(CGFloat(progress) * 30)
                let wake = [Ramp.blue[4], Ramp.blue[3], Ramp.blue[2], Ramp.blue[2]]
                for age in 1...4 {
                    let x = snap(head - direction * CGFloat(age) * 3)
                    guard x >= 0, x <= 30 else { continue }
                    cell(x, 3, wake[age - 1])
                    if age <= 2, (Int(x / 3) + age) % 2 == 0 {
                        cell(x, 0, wake[age]); cell(x, 6, wake[age])
                    }
                }
                for row in 0..<3 { cell(head, CGFloat(row) * 3, Tok.text) }
            }
        }
        .frame(width: 32, height: 8)
        .accessibilityHidden(true)
    }
}

/// Shown after about 2 s of listening if the microphone never produced a signal.
struct NoSignalShelf: View {
    var body: some View {
        HStack(spacing: 8) {
            Icon(.mic, size: 14, tint: Tok.statusBad)
            Text("No sound yet. Check your microphone.").appType(.caption).foregroundStyle(Tok.text2)
        }
        .frame(maxWidth: .infinity).frame(height: 32)
    }
}