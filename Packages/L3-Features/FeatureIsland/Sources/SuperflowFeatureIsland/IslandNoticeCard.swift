import Foundation
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// "Was that accidental?" — the six-second hold after a long Escape.
///
/// The microphone is already closed by the time this card appears, so the card
/// does not pretend to resume. It keeps the words: Undo copies them to the
/// clipboard and says so, and the countdown is drawn in whole cells rather than
/// a spinner, so the deadline is legible at a glance.
struct UndoContent: View {
    let model: IslandModel
    let undo: IslandUndo

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if let bundleID = undo.bundleID {
                        AppIcon(bundleID: bundleID, size: 20)
                    } else {
                        Icon(.undo, size: 14, weight: .medium, tint: Ramp.blue[4])
                            .frame(width: 20, height: 20)
                    }
                    Text("Was that accidental?")
                        .appType(.label)
                        .foregroundStyle(Tok.text)
                        .lineLimit(1)
                }
                .padding(.leading, pad)
                .frame(maxWidth: .infinity, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                HStack(spacing: 8) {
                    UndoTimer(remaining: model.undoRemaining, total: IslandModel.undoWindow)
                    BarIconButton(glyph: .close, label: "Dismiss") { model.send(.dismissed) }
                }
                .padding(.trailing, pad - 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: geometry.band)

            HStack(spacing: 12) {
                if undo.isEmpty {
                    Text("No words were captured.")
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(undo.text.replacingOccurrences(of: "\n", with: " "))
                        .appType(.reading)
                        .foregroundStyle(Tok.text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                        .modifier(EdgeFade(length: 32))
                }

                AppButton(model.copied ? "Copied" : "Undo",
                          glyph: model.copied ? .checkmark : .undo,
                          kind: .primary,
                          height: 28,
                          enabled: !undo.isEmpty) {
                    model.keepUndo(undo)
                }
                .frame(width: 88)
            }
            .padding(.top, IslandLayout.cardGap)
            .padding(.horizontal, pad)
            .frame(height: IslandLayout.cardRow)
            .animation(.snappy(duration: 0.20), value: model.copied)

            HStack(spacing: 12) {
                Text(undo.isEmpty
                     ? "Nothing to keep. Press fn and try again."
                     : "Escape stopped it. Undo copies the words back.")
                Spacer(minLength: 0)
                if !undo.isEmpty {
                    Text("⌘V")
                        .monospacedDigit()
                }
            }
            .appType(.caption)
            .foregroundStyle(Tok.text2)
            .lineLimit(1)
            .padding(.top, IslandLayout.cardRowGap)
            .padding(.horizontal, pad)
            .frame(height: IslandLayout.cardMeta, alignment: .leading)

            Spacer(minLength: 0)
        }
    }
}

/// An OS-style notice that lands in the notch instead of Notification Centre.
struct NoticeContent: View {
    let model: IslandModel
    let notice: IslandNotice

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    NoticeMark()
                        .frame(width: 20, height: 20)
                    Text("Superflow")
                        .appType(.label)
                        .foregroundStyle(Tok.text)
                        .lineLimit(1)
                }
                .padding(.leading, pad)
                .frame(maxWidth: .infinity, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                BarIconButton(glyph: .close, label: "Dismiss") { model.send(.dismissed) }
                    .padding(.trailing, pad - 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: geometry.band)

            Text(notice.title)
                .appType(.reading)
                .foregroundStyle(Tok.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, IslandLayout.cardGap)
                .padding(.horizontal, pad)
                .frame(height: IslandLayout.cardRow)

            Text(notice.detail)
                .appType(.caption)
                .foregroundStyle(Tok.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, IslandLayout.cardRowGap)
                .padding(.horizontal, pad)
                .frame(height: IslandLayout.cardMeta)

            Spacer(minLength: 0)
        }
    }
}
