import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// The assistant card: a streamed answer about the latest transcript.
/// Titles and actions speak state; the answer itself scrolls nothing — it is
/// capped at the card, and the full text lives in History.
struct AssistantCard: View {
    let model: IslandModel

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry
        let side = (model.box.body.width - geometry.notch.width) / 2

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    PixelBitmap(rows: PixelBitmap.spark, cell: 2, gap: 1, tone: Ramp.blue[4])
                    Text("Assistant")
                        .appType(.label)
                        .foregroundStyle(Tok.text)
                }
                .fixedSize()
                .padding(.leading, pad)
                .frame(width: side, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                BarIconButton(glyph: .close, label: "Close") {
                    model.assistantCancel()
                }
                .padding(.trailing, pad - 8)
                .frame(width: side, alignment: .trailing)
            }
            .frame(height: geometry.band)

            VStack(alignment: .leading, spacing: 12) {
                if model.assistantStatus == .idle {
                    Text("Ask about your latest transcript.")
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                        .islandReveal(0)
                } else if model.assistantStatus == .thinking {
                    Text("Thinking…")
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                        .islandReveal(0)
                } else if model.assistantStatus == .streaming || model.assistantStatus == .done || model.assistantStatus == .truncated {
                    Text(model.assistantAnswer)
                        .appType(.reading)
                        .foregroundStyle(Tok.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(6)
                        .accessibilityLabel("Assistant answer")
                        .islandReveal(0)
                } else if case .failed(let message) = model.assistantStatus {
                    Text(message)
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                        .accessibilityLabel("Assistant error")
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
                        if model.assistantAnswer.contains("key") || model.assistantAnswer.contains("Key") {
                            AppButton("Open Intelligence", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                                model.assistantOpenSettings()
                            }
                        }
                    case .truncated:
                        AppButton("Continue", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                            model.assistantRetry()
                        }
                    case .failed:
                        if model.assistantAnswer.contains("key") || model.assistantAnswer.contains("Key") {
                            AppButton("Open Intelligence", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                                model.assistantOpenSettings()
                            }
                        } else {
                            AppButton("Retry", glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                                model.assistantRetry()
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
