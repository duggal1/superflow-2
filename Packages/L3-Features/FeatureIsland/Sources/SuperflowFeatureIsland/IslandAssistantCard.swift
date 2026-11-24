import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// The assistant card: a streamed answer about the latest transcript.
/// Titles and actions speak state; the answer tile truncates with a fade and
/// stays selectable, the full text living in History.
struct AssistantCard: View {
    let model: IslandModel

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry
        let side = (model.box.body.width - geometry.notch.width) / 2

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Assistant")
                    .appType(.label)
                    .foregroundStyle(Tok.text)
                    .padding(.leading, pad)
                    .frame(width: side, alignment: .leading)
                    .accessibilityLabel("Assistant")

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                BarIconButton(glyph: .close, label: "Dismiss") {
                    model.assistantCancel()
                }
                .padding(.trailing, pad - 8)
                .frame(width: side, alignment: .trailing)
            }
            .frame(height: geometry.band)

            VStack(alignment: .leading, spacing: 12) {
                switch model.assistantStatus {
                case .thinking:
                    IslandWait()
                        .islandReveal(0)
                case .streaming, .done, .truncated:
                    Text(model.assistantAnswer)
                        .appType(.reading)
                        .lineSpacing(6)
                        .foregroundStyle(Tok.text)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52,
                               alignment: .topLeading)
                        .modifier(AssistantFade(active: model.assistantAnswer.count > 120))
                        .padding(12)
                        .textSelection(.enabled)
                        .background(Tok.well,
                                    in: .rect(cornerRadius: Radius.nested, style: .continuous))
                        .accessibilityLabel("Assistant answer")
                        .islandReveal(0)
                case .failed(let message):
                    Text(message)
                        .appType(.reading)
                        .lineSpacing(6)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                        .accessibilityLabel("Assistant error")
                        .islandReveal(0)
                case .idle:
                    Text("Ask about your latest transcript.")
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                        .islandReveal(0)
                }

                HStack(spacing: 8) {
                    switch model.assistantStatus {
                    case .idle:
                        AppButton("Help", glyph: nil, kind: .primary, height: IslandLayout.actionHeight) {
                            model.assistantHelp()
                        }
                    case .thinking, .streaming:
                        AppButton("Cancel", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                            model.assistantCancel()
                        }
                    case .done:
                        if model.assistantCanDeeper {
                            AppButton("Go deeper", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                                model.assistantDeeper()
                            }
                        }
                    case .truncated:
                        AppButton("Continue", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                            model.assistantRetry()
                        }
                    case .failed:
                        AppButton("Retry", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                            model.assistantRetry()
                        }
                        if model.assistantNeedsSettings {
                            AppButton("Open Intelligence", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                                model.assistantOpenSettings()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .islandReveal(1)
            }
            .padding(.top, IslandLayout.cardGap)
            .padding(.horizontal, pad)
            .padding(.bottom, pad)

            Spacer(minLength: 0)
        }
    }
}

private struct AssistantFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.modifier(EdgeFadeBottom(length: 20))
        } else {
            content
        }
    }
}
