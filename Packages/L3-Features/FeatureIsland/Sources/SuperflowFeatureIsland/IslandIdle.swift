import SuperflowDesignSystem
import SwiftUI

/// Resting state when "Always show Island" is on: a five-cell lamp on the notch's
/// lower edge. Nothing else is drawn at rest, so the notch still looks like a
/// notch and the lamp is the only sign the Island is listening for a click.
struct IdleMark: View {
    let model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.prefs.alwaysOn {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                IdleLampView(reduceMotion: reduceMotion)
                    .padding(.bottom, 3)
            }
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

struct IdleLampView: View {
    let reduceMotion: Bool
    @Environment(\.displayScale) private var scale

    var body: some View {
        let grid = IslandPixelGrid(scale: scale)
        TimelineView(.animation(minimumInterval: 0.18, paused: reduceMotion)) { timeline in
            let head = reduceMotion ? 2 : IdleLampMotion.head(at: timeline.date)
            Canvas { context, _ in
                for index in 0..<5 {
                    let tone = Ramp.blue[max(1, 4 - abs(index - head))]
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
    static func head(at date: Date) -> Int {
        let step = Int(floor(date.timeIntervalSinceReferenceDate / 0.18))
        let position = (step % 8 + 8) % 8
        return position <= 4 ? position : 8 - position
    }
}

/// Hover on the resting Island: today's words, rolling. Without "Always show
/// Island" there is nothing to report yet, so a single blue pixel says the notch
/// noticed the pointer.
struct HoverShelf: View {
    let model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if model.prefs.alwaysOn {
                HStack(spacing: 8) {
                    Text(model.today.formatted())
                        .appType(.label)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text)
                        .contentTransition(.numericText())
                    Text("words today")
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                }
                .frame(height: 28)
            } else {
                Rectangle()
                    .fill(Ramp.blue[4])
                    .frame(width: 2, height: 2)
                    .padding(.bottom, 1)
            }
        }
        .accessibilityHidden(true)
    }
}
