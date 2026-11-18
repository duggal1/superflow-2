import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Recessed answer tile. The well is a background step, never a border; a row
/// of cells at the foot of the tile is the only ornament, and it reads as a
/// signal rather than decoration.
struct AnswerTile: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.sm) {
            Text(text)
                .appType(IslandTokens.TypeRole.body)
                .foregroundStyle(IslandTokens.Color.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(EdgeFade(length: IslandTokens.Size.cardPad))
            PixelRule(tone: IslandRamp.step(1))
        }
        .padding(IslandTokens.Space.md)
        .background(IslandTokens.Color.field,
                    in: .rect(cornerRadius: IslandTokens.Radius.chip))
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

/// The last dictations. Each row is a pixel register: a cell caret, one faded
/// line and a time column. Clicking a line copies it.
struct HistoryView: View {
    let count: Int
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PixelHeading(glyph: PixelGlyphs.history, title: "Recent",
                         tone: IslandRamp.step(4), caption: "\(count) saved")
                .frame(height: IslandTokens.Size.row)
            PixelFlowRail(active: 0)

            VStack(spacing: 0) {
                if context.history.isEmpty {
                    HStack(spacing: IslandTokens.Space.sm) {
                        PixelBitmap(rows: PixelGlyphs.history, cell: PixelInstrument.cell,
                                    gap: PixelInstrument.gap, tone: IslandRamp.step(2))
                        Text("Nothing dictated yet.")
                            .appType(IslandTokens.TypeRole.body)
                            .foregroundStyle(IslandTokens.Color.ink2)
                    }
                    .frame(maxWidth: .infinity, minHeight: IslandTokens.Size.row * 2)
                } else {
                    ForEach(Array(context.history.enumerated()), id: \.element.id) { i, item in
                        HistoryRow(item: item, context: context)
                            .modifier(RowReveal(index: i))
                    }
                }
            }
            Spacer(minLength: 0)
            PixelRule(tone: IslandRamp.step(1))
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed()
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
                PixelBitmap(rows: PixelGlyphs.compose, cell: 1, gap: 0,
                            tone: hover ? IslandRamp.step(4) : IslandRamp.step(3))
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(IslandTokens.Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(item.words) words").appType(IslandTokens.TypeRole.caption)
                    .foregroundStyle(IslandTokens.Color.ink2).monospacedDigit()
                    .opacity(hover ? 0 : 1)
                PixelBitmap(rows: PixelBitmap.check, cell: 1, gap: 0, tone: IslandRamp.step(4))
                    .opacity(hover ? 1 : 0)
            }
            .onHover { hover = $0 }
        }
    }
}

// MARK: settings

/// Prompt theme selector hosted inside the Island. The selected theme is a lit
/// pixel box; the others are empty rings. No native control, no popover.
struct SettingsView: View {
    let theme: String
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            PixelHeading(glyph: PixelGlyphs.settings, title: "Prompt theme", tone: IslandRamp.step(4))
            PixelFlowRail(active: 0)
            VStack(spacing: IslandTokens.Space.xs) {
                ForEach(Array(IslandTokens.Theme.allCases.enumerated()), id: \.element) { i, option in
                    ThemeRow(title: option.rawValue, selected: theme == option.rawValue) {
                        context.actions.theme(option.rawValue)
                    }
                    .modifier(RowReveal(index: i))
                }
            }
            Spacer(minLength: 0)
            PixelRule(tone: IslandRamp.step(1))
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed()
    }
}

private struct ThemeRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        RowButton(title, height: IslandTokens.Size.row, selected: selected, action: action) {
            HStack(spacing: IslandTokens.Space.sm) {
                PixelBitmap(rows: selected ? PixelBitmap.disc : PixelGlyphs.listening,
                            cell: 1, gap: 0,
                            tone: selected ? IslandRamp.step(4) : IslandRamp.step(2))
                Text(title).appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
            }
        }
    }
}
