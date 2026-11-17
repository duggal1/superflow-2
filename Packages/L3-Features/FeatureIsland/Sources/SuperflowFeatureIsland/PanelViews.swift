import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Recessed answer tile with the edge fade used across the island.
struct AnswerTile: View {
    let text: String
    var body: some View {
        Text(text)
            .appType(IslandTokens.TypeRole.body)
            .foregroundStyle(IslandTokens.Color.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(IslandTokens.Space.md)
            .background(IslandTokens.Color.field,
                        in: .rect(cornerRadius: IslandTokens.Radius.chip))
            .modifier(EdgeFade(length: IslandTokens.Size.cardPad))
    }
}

/// A row that rises 35 ms after the one above it. Reduce Motion shows it whole.
struct RowReveal: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.islandReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : IslandTokens.Space.sm)
            .onAppear {
                guard !reduce else { return }
                withAnimation(.smooth(duration: IslandTokens.Duration.contentIn)
                    .delay(Double(index) * IslandTokens.Duration.rowStagger)) {
                    shown = true
                }
            }
    }
}

// MARK: history

/// The last dictations. Clicking a line copies it; the time column is reserved
/// so nothing reflows on hover.
struct HistoryView: View {
    let count: Int
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                Text("\(count) saved").appType(IslandTokens.TypeRole.caption)
                    .foregroundStyle(IslandTokens.Color.ink2).monospacedDigit()
            }
            .frame(height: IslandTokens.Size.row)

            VStack(spacing: 0) {
                if context.history.isEmpty {
                    Text("Nothing dictated yet.")
                        .appType(IslandTokens.TypeRole.body)
                        .foregroundStyle(IslandTokens.Color.ink2)
                        .frame(maxWidth: .infinity, minHeight: IslandTokens.Size.row * 2)
                } else {
                    ForEach(Array(context.history.enumerated()), id: \.element.id) { i, item in
                        HistoryRow(item: item, context: context)
                            .modifier(RowReveal(index: i))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HistoryRow: View {
    let item: IslandTranscript
    let context: FlowContext
    @State private var hover = false

    var body: some View {
        RowButton("Copy: \(item.text)", height: IslandTokens.Size.row) {
            context.actions.copyTranscript(item)
        } content: {
            HStack(spacing: IslandTokens.Space.md) {
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(IslandTokens.Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(item.words) words").appType(IslandTokens.TypeRole.caption)
                    .foregroundStyle(IslandTokens.Color.ink2).monospacedDigit()
                    .opacity(hover ? 0 : 1)
                IconView(.copy, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.ink2)
                    .opacity(hover ? 1 : 0)
            }
            .onHover { hover = $0 }
        }
    }
}

// MARK: settings

/// Prompt theme selector hosted inside the Island. No native popover or menu:
/// every control is an in-island view, which also keeps the surface stealthy.
struct SettingsView: View {
    let theme: String
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack {
                Text("Prompt theme").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                           tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            }
            VStack(spacing: IslandTokens.Space.xs) {
                ForEach(Array(IslandTokens.Theme.allCases.enumerated()), id: \.element) { i, option in
                    ThemeRow(title: option.rawValue, selected: theme == option.rawValue) {
                        context.actions.theme(option.rawValue)
                    }
                    .modifier(RowReveal(index: i))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ThemeRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        RowButton(title, height: IslandTokens.Size.row, selected: selected, action: action) {
            HStack(spacing: IslandTokens.Space.sm) {
                IconView(selected ? .checkmark : .circle, size: IslandTokens.Size.glyph,
                         tint: selected ? IslandTokens.Color.accent : IslandTokens.Color.ink2)
                Text(title).appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
            }
        }
    }
}
