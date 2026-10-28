import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Click the always-visible Island and it grows downward into your last five
/// dictations. Up/down move, Return copies, Space expands, Escape closes.
struct HistoryPanel: View {
    let model: IslandModel

    @State private var cursor = 0
    @State private var open: String?
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

                BarIconButton(glyph: .close, label: "Close") { model.send(.dismissed) }
                    .padding(.trailing, pad - 8)
                    .frame(width: side, alignment: .trailing)
            }
            .frame(height: geometry.band)

            Group {
                if rows.isEmpty {
                    EmptyState("Nothing dictated yet.",
                               message: "Hold fn and speak.",
                               density: .pane)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 2) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    HistoryRow(model: model, transcript: row,
                                               selected: index == cursor,
                                               expanded: open == row.id) {
                                        cursor = index
                                        open = open == row.id ? nil : row.id
                                    }
                                    .id(row.id)
                                }
                            }
                        }
                        .onChange(of: cursor) {
                            if rows.indices.contains(cursor) {
                                proxy.scrollTo(rows[cursor].id)
                            }
                        }
                        .onChange(of: open) {
                            if let open { proxy.scrollTo(open, anchor: .top) }
                        }
                    }
                }
            }
            .frame(height: 240)
            .padding(.top, 12)
            .padding(.horizontal, 12)

            HStack(spacing: 16) {
                keyHint("↑↓", "Move")
                keyHint("⏎", "Copy")
                keyHint("esc", "Close")
                Spacer(minLength: 0)
                AppButton("Open History", glyph: nil, kind: .quiet, height: 24) {
                    model.openHistory()
                }
            }
            .padding(.horizontal, pad)
            .frame(height: 44)

            Spacer(minLength: 0)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            cursor = 0
            open = nil
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
        .onKeyPress(.space) {
            if rows.indices.contains(cursor) {
                open = open == rows[cursor].id ? nil : rows[cursor].id
            }
            return .handled
        }
        .onKeyPress(.escape) {
            model.send(.dismissed)
            return .handled
        }
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            HintKey(label: key)
            Text(label)
                .appType(.caption)
                .foregroundStyle(Tok.text2)
        }
    }
}

/// One dictation. The whole row toggles the expansion; the copy button is always
/// visible, because a hover-only control is invisible to keyboard and VoiceOver.
struct HistoryRow: View {
    let model: IslandModel
    let transcript: IslandTranscript
    let selected: Bool
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        let copied = model.copiedID == transcript.id
        HStack(spacing: 4) {
            RowButton("\(transcript.appName ?? "Dictation"), \(Humanize.when(transcript.date))",
                      selected: selected, action: onToggle) {
                HStack(spacing: 12) {
                    TargetIcon(bundleID: transcript.bundleID)
                    VStack(alignment: .leading, spacing: 2) {
                        preview
                        HStack(spacing: 12) {
                            Text(Humanize.when(transcript.date))
                            Text(Humanize.words(transcript.words)).monospacedDigit()
                        }
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 12)
            }

            BarIconButton(glyph: copied ? .checkmark : .copy,
                          label: "Copy cleaned transcript") {
                model.copy(transcript)
            }
        }
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .overlay(alignment: .leading) {
            // A pixel caret, not a stroke.
            if selected {
                Rectangle()
                    .fill(Ramp.blue[4])
                    .frame(width: 2, height: 16)
            }
        }
        .animation(.snappy(duration: 0.20), value: copied)
    }

    @ViewBuilder private var preview: some View {
        if expanded {
            Text(transcript.text)
                .appType(.label)
                .foregroundStyle(Tok.text)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(transcript.text.replacingOccurrences(of: "\n", with: " "))
                .appType(.label)
                .foregroundStyle(Tok.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
                .modifier(EdgeFade(length: 32))
        }
    }
}
