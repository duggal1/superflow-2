import SuperflowDesignSystem
import SwiftUI

/// The rolling clock. Each digit rolls only when it changes: the old digit
/// leaves upward while the new one comes up from below, with no blur and no
/// gradient. The roll is the same critically damped curve as the springs and it
/// runs at the display rate.
struct RollingClock: View {
    let since: Date
    /// `.label` for the wings, `.metric` for the meeting panel.
    var role: AppType = .label

    private static func format(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        let big = role == .metric
        let dw: CGFloat = big ? 17 : 8
        let h: CGFloat = big ? 34 : 16
        TimelineView(.animation) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(since))
            let seconds = Int(elapsed), fraction = elapsed - Double(seconds)
            // 0 at the tick, about 0.93 after 200 ms, flat for the rest of the second.
            let roll = seconds == 0 ? 1 : 1 - exp(-22 * fraction) * (1 + 22 * fraction)
            let current = Array(Self.format(seconds))
            let previous = Array(Self.format(max(0, seconds - 1)))
            HStack(spacing: 0) {
                ForEach(current.indices, id: \.self) { index in
                    // Align from the right: a new hour is one extra leading slot.
                    let offset = index - (current.count - previous.count)
                    let before: Character = (seconds > 0 && offset >= 0 && offset < previous.count)
                        ? previous[offset]
                        : current[index]
                    ClockSlot(now: current[index], before: before, roll: roll,
                              dw: dw, h: h, role: role)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(Self.format(seconds))
        }
        .frame(height: h)
    }
}

private struct ClockSlot: View {
    let now: Character
    let before: Character
    let roll: Double
    let dw: CGFloat
    let h: CGFloat
    let role: AppType

    var body: some View {
        let moving = now != before && now != ":"
        ZStack {
            if moving {
                glyph(before)
                    .offset(y: -h * 0.7 * roll)
                    .opacity(1 - roll)
                glyph(now)
                    .offset(y: h * 0.7 * (1 - roll))
                    .opacity(roll)
            } else {
                glyph(now)
            }
        }
        .frame(width: now == ":" ? (role == .metric ? 8 : 4) : dw, height: h)
        .clipped()
    }

    private func glyph(_ character: Character) -> some View {
        Text(String(character))
            .appType(role)
            .monospacedDigit()
            .foregroundStyle(character == ":" ? Tok.text2 : Tok.text)
    }
}
