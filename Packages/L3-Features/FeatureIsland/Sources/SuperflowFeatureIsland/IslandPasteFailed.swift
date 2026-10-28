import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Paste failed. The card opens, shows the cleaned text truncated with a fade,
/// and closes itself 0.9 s after Copy. "Paste again" re-inserts the same text
/// through the app's inserter; the card never guesses why the field refused.
struct PasteFailedCard: View {
    let model: IslandModel
    let transcript: IslandTranscript

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry
        let side = (model.box.body.width - geometry.notch.width) / 2

        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                Text("Not pasted.").appType(.label).fixedSize()
                Text("Not pasted").appType(.caption).fixedSize()
            }
            .foregroundStyle(Tok.text)
            .padding(.leading, pad)
            .frame(width: side, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                BarIconButton(glyph: .close, label: "Dismiss") { model.send(.dismissed) }
                    .padding(.trailing, pad - 8)
            }
            .frame(height: geometry.band)

            VStack(alignment: .leading, spacing: 12) {
                Text(transcript.text.replacingOccurrences(of: "\n", with: " "))
                    .appType(.reading)
                    .foregroundStyle(Tok.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60,
                           alignment: .topLeading)
                    .modifier(FadeIf(active: transcript.text.count > 120))
                    .padding(12)
                    .background(Tok.control,
                                in: .rect(cornerRadius: Radius.nested, style: .continuous))

                HStack(spacing: 12) {
                    TargetIcon(bundleID: transcript.bundleID)
                    if let appName = transcript.appName {
                        Text(appName)
                            .appType(.caption)
                            .foregroundStyle(Tok.text2)
                            .lineLimit(1)
                    }
                    Text(Humanize.words(transcript.words))
                        .appType(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                    Spacer(minLength: 0)
                    AppButton("Paste again", glyph: nil, kind: .secondary, height: 28) {
                        model.retryPaste(transcript)
                    }
                    .frame(width: 104)
                    AppButton(model.copied ? "Copied" : "Copy",
                              glyph: model.copied ? .checkmark : nil,
                              kind: model.copied ? .secondary : .primary,
                              height: 28) {
                        model.copy(transcript)
                    }
                    .frame(width: 88)
                }
                .frame(height: 28)
                .animation(.snappy(duration: 0.20), value: model.copied)
            }
            .padding(.top, IslandLayout.cardGap)
            .padding(.horizontal, pad)

            Spacer(minLength: 0)
        }
    }
}

private struct FadeIf: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.modifier(EdgeFadeBottom(length: 20))
        } else {
            content
        }
    }
}
