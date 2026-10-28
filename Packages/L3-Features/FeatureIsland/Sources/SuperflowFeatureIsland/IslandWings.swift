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
        let wing = IslandLayout.wingWidth(model.phase)

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
        case .listening, .handsFree, .meeting:
            PixelWaveform(history: model.waveform.history)
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
}
