import Foundation
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// One component, two kinds. The failure card and the click-the-notch card share
/// the same size and layout so they morph into each other on one curve.
struct CardContent: View {
    enum Kind { case failed, recent }

    let model: IslandModel
    let kind: Kind
    let transcript: IslandTranscript?

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .padding(.leading, pad)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                trailing
                    .padding(.trailing, kind == .failed ? pad - 8 : pad)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: geometry.band)

            row
                .padding(.top, IslandLayout.cardGap)
                .padding(.horizontal, pad)

            Spacer(minLength: 0)
        }
    }

    /// The band beside the notch is only about 100 pt wide. A failure spends it
    /// on the one word that matters; a recent dictation spends it identifying the
    /// app. Never both.
    private var leading: some View {
        HStack(spacing: 8) {
            if kind == .recent {
                if let bundleID = transcript?.bundleID {
                    AppIcon(bundleID: bundleID, size: 20)
                } else {
                    Icon(.mic, size: 14, tint: Tok.text2)
                        .frame(width: 20, height: 20)
                }
            }
            Text(title)
                .appType(.label)
                .foregroundStyle(Tok.text)
                .lineLimit(1)
        }
    }

    /// The band beside the notch is only about 100 pt wide, so the title stays
    /// short on purpose. The transcript below carries the detail.
    private var title: String {
        switch kind {
        case .failed: "Not pasted."
        case .recent: transcript?.appName ?? "Dictation"
        }
    }

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .failed:
            BarIconButton(glyph: .close, label: "Dismiss") { model.send(.dismissed) }
        case .recent:
            if let transcript {
                Text(Humanize.when(transcript.date))
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
            }
        }
    }

    @ViewBuilder private var row: some View {
        if let transcript {
            HStack(spacing: 12) {
                Text(transcript.text.replacingOccurrences(of: "\n", with: " "))
                    .appType(.reading)
                    .foregroundStyle(Tok.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .modifier(EdgeFade(length: 32))

                AppButton(model.copied ? "Copied" : "Copy",
                          glyph: model.copied ? .checkmark : nil,
                          kind: kind == .failed && !model.copied ? .primary : .secondary,
                          height: 28) {
                    model.copy(transcript)
                }
                // Fixed width: the label changes, the transcript's line does not.
                .frame(width: 88)
            }
            .frame(height: IslandLayout.cardRow)
            .animation(.snappy(duration: 0.20), value: model.copied)
        } else {
            Text("Hold fn and speak.")
                .appType(.reading)
                .foregroundStyle(Tok.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: IslandLayout.cardRow)
        }
    }
}
