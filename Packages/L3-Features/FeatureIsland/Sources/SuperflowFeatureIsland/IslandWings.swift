import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Compact state: what you are talking to on the left of the notch, one signal on
/// the right. Both hug their outer edge and stay centred on the band.
///
/// The right signal is the pixel meter for every capturing state, including the
/// cleanup that follows the release, so the Island never goes blank between the
/// microphone closing and the text landing.
struct WingsContent: View {
    let model: IslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let geometry = model.geometry
        let gap = geometry.hasNotch ? geometry.notch.width : IslandLayout.nonNotchGap
        let wing = IslandLayout.wingWidth(model.phase, gap: gap)

        HStack(spacing: 0) {
            leading
                .padding(.leading, wing == IslandLayout.wing ? IslandLayout.wingInset : 12)
                .frame(width: wing, alignment: .leading)

            Color.clear.frame(width: gap)

            trailing
                .padding(.trailing, IslandLayout.wingInset)
                .frame(width: wing, alignment: .trailing)
        }
        .frame(height: geometry.band)
    }

    @ViewBuilder private var leading: some View {
        switch model.phase {
        case .handsFree:
            ModeLabel(text: "Hands-free", glyph: .waveform)
        case .meeting:
            ModeLabel(text: "Meeting", glyph: .meetings)
        case .listening, .processing, .landed:
            if let bundleID = model.target?.bundleID {
                AppIcon(bundleID: bundleID, size: 20)
            } else {
                Icon(.mic, size: 14, tint: Tok.text)
            }
        case .idle, .hover, .failed, .recent, .undo, .notice:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch model.phase {
        case .listening, .handsFree:
            PixelWaveform(history: model.waveform.history)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .meeting:
            HStack(spacing: 8) {
                Text(Self.clock(model.elapsed))
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
                    .contentTransition(.numericText(value: Double(model.elapsed)))
                    .accessibilityLabel("Meeting running for \(Self.spoken(model.elapsed))")
                PixelWaveform(history: model.waveform.history)
            }
            .transition(.islandContent(reduceMotion: reduceMotion))
        case .processing:
            PixelWaveform(history: model.waveform.history, ambient: true)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .landed:
            Icon(.checkmark, size: 14, weight: .medium, tint: Tok.text)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .idle, .hover, .failed, .recent, .undo, .notice:
            EmptyView()
        }
    }

    /// "4:12", or "1:04:12" once a meeting passes the hour. No leading zero on
    /// the minutes: the readout is a duration, not a clock.
    private static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private static func spoken(_ seconds: Int) -> String {
        let total = max(0, seconds), m = total / 60, s = total % 60
        guard m > 0 else { return "\(s) seconds" }
        return "\(m) minutes \(s) seconds"
    }
}
