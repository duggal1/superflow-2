import Foundation
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// One component, two kinds. The failure card and the click-the-notch card share
/// the same size and layout so they morph into each other on one curve.
///
/// Every card is band + transcript + meta: the band says what happened, the
/// transcript is the thing you came for, and the meta says what to do next. No
/// icon in the failure band: beside the notch there are only about 84 points.
struct CardContent: View {
    enum Kind { case failed, recent }

    let model: IslandModel
    let kind: Kind
    let transcript: IslandTranscript?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            meta
                .padding(.top, IslandLayout.cardRowGap)
                .padding(.horizontal, pad)

            Spacer(minLength: 0)
        }
    }

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(Tok.text2)
            }
        }
    }

    @ViewBuilder private var row: some View {
        if let transcript {
            HStack(spacing: IslandLayout.actionGap) {
                Text(transcript.text.replacingOccurrences(of: "\n", with: " "))
                    .appType(.reading)
                    .foregroundStyle(Tok.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .modifier(EdgeFade(length: 32))
                    .padding(.horizontal, 12)
                    .frame(height: IslandLayout.transcriptRow)
                    .background(Tok.well, in: .rect(cornerRadius: Radius.field))

                AppButton(model.copied ? "Copied" : "Copy",
                          glyph: model.copied ? .checkmark : nil,
                          kind: model.copied ? .secondary : .sapphire,
                          height: IslandLayout.actionHeight, minimumWidth: 80) {
                    model.copy(transcript)
                }
            }
            .frame(height: IslandLayout.transcriptRow)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: model.copied)
        } else {
            Text("Hold fn and speak.")
                .appType(.reading)
                .foregroundStyle(Tok.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: IslandLayout.cardRow)
        }
    }

    @ViewBuilder private var meta: some View {
        HStack(spacing: 12) {
            switch kind {
            case .failed:
                Text(transcript.map(pasteLine) ?? "The field refused the paste.")
                Spacer(minLength: 0)
                Text("⌘V")
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
            case .recent:
                if let transcript {
                    Text(Humanize.words(transcript.words))
                        .monospacedDigit()
                    Text("Dictation")
                } else {
                    Text("Nothing stored yet.")
                }
                Spacer(minLength: 0)
            }
        }
        .appType(.caption)
        .foregroundStyle(Tok.text2)
        .lineLimit(1)
        .frame(height: IslandLayout.cardMeta, alignment: .leading)
    }

    private func pasteLine(_ transcript: IslandTranscript) -> String {
        guard let name = transcript.appName else { return "The field refused the paste." }
        return "Paste blocked in \(name)."
    }
}
