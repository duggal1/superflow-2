import SuperflowDesignSystem
import SwiftUI

/// The five-cell lamp on the resting notch's lower edge. Kept as one shared
/// implementation so the idle state and the motion test agree on its geometry.
struct IdleLampView: View {
    let reduceMotion: Bool
    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        TimelineView(.animation(minimumInterval: 0.18, paused: reduceMotion)) { timeline in
            let head = reduceMotion ? 2 : IdleLampMotion.head(at: timeline.date)
            Canvas { context, _ in
                for index in 0..<5 {
                    let tone = IslandRamp.step(max(1, 4 - abs(index - head)))
                    context.fill(Path(grid.rect(CGRect(x: CGFloat(index) * 3, y: 0,
                                                      width: 2, height: 2))),
                                 with: .color(tone), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: grid.length(14), height: grid.length(2))
        .accessibilityHidden(true)
    }
}

enum IdleLampMotion {
    /// The lit cell walks 0→4→0, one step every 180 ms. Pure, so the headless
    /// motion test can sample it without a display frame.
    static func head(at date: Date) -> Int {
        let step = Int(floor(date.timeIntervalSinceReferenceDate / 0.18))
        let position = (step % 8 + 8) % 8
        return position <= 4 ? position : 8 - position
    }
}
