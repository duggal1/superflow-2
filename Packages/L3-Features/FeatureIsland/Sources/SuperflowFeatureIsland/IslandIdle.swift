import SuperflowDesignSystem
import SwiftUI

/// Resting state when "Always show Island" is on: a five-cell lamp on the notch's
/// lower edge. Nothing else is drawn at rest, so the notch still looks like a
/// notch and the lamp is the only sign the Island is listening for a click.
struct IdleMark: View {
    let model: IslandModel

    var body: some View {
        if model.prefs.alwaysOn {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Canvas { context, _ in
                    let tones = [Ramp.blue[1], Ramp.blue[2], Ramp.blue[4], Ramp.blue[2], Ramp.blue[1]]
                    for (index, tone) in tones.enumerated() {
                        context.fill(Path(CGRect(x: CGFloat(index) * 3, y: 0,
                                                 width: 2, height: 2)),
                                     with: .color(tone),
                                     style: FillStyle(antialiased: false))
                    }
                }
                .frame(width: 14, height: 2)
                .padding(.bottom, 3)
            }
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
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
