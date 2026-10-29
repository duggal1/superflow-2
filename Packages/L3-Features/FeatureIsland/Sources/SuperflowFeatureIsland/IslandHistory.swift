import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Click the always-visible Island and it grows downward into your last five
/// dictations. Up/down move, Return copies, Escape or a click on the notch
/// closes. There are no per-row controls: the row itself is the button.
struct HistoryPanel: View {
    let model: IslandModel

    @State private var cursor = 0
    @FocusState private var focused: Bool

    private var pad: CGFloat { IslandLayout.cardPad }

    var body: some View {
        let geometry = model.geometry
        let rows = model.history
        let side = (model.box.body.width - geometry.notch.width) / 2

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Recent")
                    .appType(.label)
                    .foregroundStyle(Tok.text)
                    .padding(.leading, pad)
                    .frame(width: side, alignment: .leading)

                if geometry.hasNotch {
                    Color.clear.frame(width: geometry.notch.width)
                }

                ViewThatFits(in: .horizontal) {
                    todayLabel("words today").fixedSize()
                    todayLabel("today").fixedSize()
                }
                .accessibilityLabel("\(model.today) words today")
                .padding(.trailing, pad)
                .frame(width: side, alignment: .trailing)
            }
            .frame(height: geometry.band)

            VStack(spacing: 0) {
                if rows.isEmpty {
                    Text("Nothing dictated yet.")
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, transcript in
                        HistoryRow(model: model, transcript: transcript, selected: index == cursor)
                            .modifier(RowReveal(index: index))
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)

            HStack {
                Text("Click a line to copy it")
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
                Spacer(minLength: 0)
                AppButton("Open History", glyph: nil, kind: .quiet, height: 24) {
                    model.openHistory()
                }
            }
            .padding(.horizontal, pad)
            .frame(height: 40)

            Spacer(minLength: 0)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            cursor = 0
        }
        .onKeyPress(.upArrow) {
            cursor = max(0, cursor - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            cursor = min(max(0, rows.count - 1), cursor + 1)
            return .handled
        }
        .onKeyPress(.return) {
            if rows.indices.contains(cursor) { model.copy(rows[cursor]) }
            return .handled
        }
        .onKeyPress(.escape) {
            model.send(.dismissed)
            return .handled
        }
    }
    private func todayLabel(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text(model.today.formatted()).monospacedDigit().foregroundStyle(Tok.text)
            Text(label).foregroundStyle(Tok.text2)
        }
        .appType(.caption)
    }

}

/// One dictation. The whole row copies its cleaned text; hover and selection
/// swap the time for a copy glyph in the same fixed column, so nothing reflows.
struct HistoryRow: View {
    let model: IslandModel
    let transcript: IslandTranscript
    let selected: Bool

    @State private var hover = false

    var body: some View {
        let copied = model.copiedID == transcript.id
        HStack(spacing: 12) {
            TargetIcon(bundleID: transcript.bundleID)

            Text(transcript.text.replacingOccurrences(of: "\n", with: " "))
                .appType(.label)
                .foregroundStyle(Tok.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
                .modifier(EdgeFade(length: 32))

            ZStack(alignment: .trailing) {
                Text(Humanize.when(transcript.date))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
                    .opacity(hover || selected || copied ? 0 : 1)
                IconView(.copy, size: 14, tint: Tok.text2)
                    .opacity((hover || selected) && !copied ? 1 : 0)
                PixelBitmap(rows: PixelBitmap.check, develop: 0.14)
                    .opacity(copied ? 1 : 0)
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(fill(copied: copied),
                    in: .rect(cornerRadius: Radius.nested, style: .continuous))
        .overlay(alignment: .leading) {
            // A pixel caret, not a stroke.
            if selected {
                Rectangle()
                    .fill(Ramp.blue[4])
                    .frame(width: 2, height: 16)
            }
        }
        .contentShape(.rect)
        .accessibilityHidden(true)
        .overlay {
            SurfaceButton("Copy: \(transcript.text)") { model.copy(transcript) }
        }
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .animation(.snappy(duration: 0.20), value: copied)
    }

    private func fill(copied: Bool) -> Color {
        if copied { return Tok.accentSoft }
        return selected || hover ? Tok.control : .clear
    }
}

/// Rows rise 6 pt and fade in, 35 ms apart. Reduce Motion shows them whole.
struct RowReveal: ViewModifier {
    let index: Int

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 6)
            .onAppear {
                guard !reduce else { return }
                withAnimation(.smooth(duration: 0.30).delay(Double(index) * 0.035)) {
                    shown = true
                }
            }
    }
}
