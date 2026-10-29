import Foundation
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// "Was that a mistake?" — the six-second hold after a long Escape.
///
/// The microphone is already closed by the time this card appears, so the card
/// does not pretend to resume. It keeps the words: Undo copies them to the
/// clipboard and says so, and the countdown is a pixel rail that drains in whole
/// cells, so the deadline is legible at a glance without a spinner.
struct UndoContent: View {
    let model: IslandModel
    let undo: IslandUndo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pad: CGFloat { IslandLayout.cardPad }

    /// How much was nearly lost, in the card's own words.
    private var held: String? {
        let total = Int(undo.seconds.rounded())
        guard total >= Int(IslandModel.undoMinimumSeconds) else { return nil }
        let minutes = total / 60, seconds = total % 60
        return minutes > 0 ? "\(minutes) min \(seconds) s" : "\(seconds) s"
    }

    var body: some View {
        let geometry = model.geometry
        let side = (model.box.body.width - (geometry.hasNotch ? geometry.notch.width : 0)) / 2

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        PixelDissolve(trail: model.frozenTrail)
                        Text("Cancelled.").appType(.label).foregroundStyle(Tok.text)
                    }
                    .fixedSize()
                    PixelDissolve(trail: model.frozenTrail)
                }
                .accessibilityLabel("Cancelled")
                .padding(.leading, pad)
                .frame(width: side, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                HStack(spacing: 8) {
                    CountdownNumeral(deadline: model.undoDeadline)
                    BarIconButton(glyph: .close, label: "Dismiss") { model.send(.dismissed) }
                }
                .padding(.trailing, pad - 8)
                .frame(width: side, alignment: .trailing)
            }
            .frame(height: geometry.band)

            HStack(spacing: 12) {
                if undo.isEmpty {
                    Text("No words were captured.")
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(undo.text.replacingOccurrences(of: "\n", with: " "))
                        .appType(.reading)
                        .foregroundStyle(Tok.text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .clipped()
                        .modifier(EdgeFade(length: 32))
                }

                AppButton(model.copied ? "Copied" : "Undo",
                          glyph: model.copied ? .checkmark : .undo,
                          kind: .primary,
                          height: IslandLayout.actionHeight,
                          enabled: !undo.isEmpty, minimumWidth: 80) {
                    model.keepUndo(undo)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.top, IslandLayout.cardGap)
            .padding(.horizontal, pad)
            .frame(height: IslandLayout.cardRow)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: model.copied)

            HStack(spacing: 12) {
                Text(undo.isEmpty
                     ? "Nothing to keep. Press fn and try again."
                     : held.map { "You were \($0) in. Undo copies the words back." }
                        ?? "Escape stopped it. Undo copies the words back.")
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .modifier(EdgeFade(length: 24))
                if let deadline = model.undoDeadline {
                    PixelCountdown(deadline: deadline, total: TimeInterval(IslandModel.undoWindow))
                        .accessibilityLabel("\(model.undoRemaining) seconds left to undo")
                }
                if !undo.isEmpty {
                    Text("⌘V")
                        .monospacedDigit()
                        .fixedSize()
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
///
/// It grows out of the notch and is absorbed back into it. The band carries the
/// kind's pixel mark, the body carries the number (counted up in whole steps) or
/// the sentence, and a rail counts the seconds it has left. Only genuine
/// notifications get this far; the app's notifier gates them.
struct NoticeContent: View {
    let model: IslandModel
    let notice: IslandNotice

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NoticeMark(kind: notice.kind)
                    .frame(width: 20, height: 20)
                    .padding(.leading, pad)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                HStack(spacing: 12) {
                    if let deadline = model.noticeDeadline {
                        PixelCountdown(deadline: deadline,
                                       total: IslandModel.noticeSeconds,
                                       cells: 10)
                            .accessibilityLabel("Closes in \(model.noticeRemaining) seconds")
                    }
                    BarIconButton(glyph: .close, label: "Dismiss") { model.send(.dismissed) }
                }
                .padding(.trailing, pad - 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: geometry.band)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let value = notice.value {
                    CountUp(value: value)
                    Text(notice.kind == .streak ? "days in a row" : "words, dictated by you")
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                } else {
                    Text(notice.title)
                        .appType(.title)
                        .foregroundStyle(Tok.text)
                    Text(notice.detail)
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                }

                Spacer(minLength: 12)

                if let action = notice.action {
                    AppButton(action, glyph: nil, kind: .secondary, height: IslandLayout.actionHeight) {
                        model.openNotice(notice)
                    }
                    .fixedSize()
                }
            }
            .lineLimit(1)
            .frame(minHeight: 36)
            .padding(.top, IslandLayout.cardGap)
            .padding(.horizontal, pad)

            Spacer(minLength: 0)
        }
    }
}

/// Counts up in 14 whole steps over 0.7 s. The final frame is always the exact
/// value, and the hidden final number reserves its width so nothing reflows.
struct CountUp: View {
    let value: Int

    @State private var born = Date()
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let value = value
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduce)) { timeline in
            let progress = reduce ? 1 : min(1, timeline.date.timeIntervalSince(born) / 0.7)
            let shown = progress >= 1
                ? value
                : Int(Double(value) * (progress * 14).rounded(.down) / 14)
            ZStack(alignment: .leading) {
                Text(value.formatted()).hidden()
                Text(shown.formatted()).contentTransition(.numericText())
            }
            .appType(.metric)
            .monospacedDigit()
            .foregroundStyle(Tok.text)
        }
        .accessibilityLabel("\(value.formatted())")
    }
}
