import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Compact state: destination on the left of the notch, one signal on the right.
/// Both hug their outer edge and stay centred on the band.
struct WingsContent: View {
    let model: IslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let geometry = model.geometry
        let gap = geometry.hasNotch ? geometry.notch.width : IslandLayout.nonNotchGap

        HStack(spacing: 0) {
            leading
                .padding(.leading, IslandLayout.wingInset)
                .frame(width: IslandLayout.wing, alignment: .leading)

            Color.clear.frame(width: gap)

            trailing
                .padding(.trailing, IslandLayout.wingInset)
                .frame(width: IslandLayout.wing, alignment: .trailing)
        }
        .frame(height: geometry.band)
    }

    @ViewBuilder private var leading: some View {
        if let bundleID = model.target?.bundleID {
            AppIcon(bundleID: bundleID, size: 20)
        } else {
            Icon(.mic, size: 14, tint: Tok.text)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch model.phase {
        case .listening:
            PixelWaveform(history: model.waveform.history)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .processing:
            PixelWait()
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .landed:
            Icon(.checkmark, size: 14, weight: .medium, tint: Tok.text)
                .transition(.islandContent(reduceMotion: reduceMotion))
        case .idle, .hover, .failed, .recent:
            EmptyView()
        }
    }
}
