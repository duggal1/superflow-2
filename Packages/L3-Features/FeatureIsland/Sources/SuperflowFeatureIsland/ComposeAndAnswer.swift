import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

// MARK: compose

/// A typed question. The Intelligence host owns the field and the send glyph;
/// the Island registers the surface in pixel corners and draws its own signal
/// band underneath so the compose state reads as an instrument, not a form.
struct ComposeView: View {
    let draft: String
    let context: FlowContext

    var body: some View {
        if let hosted = context.hostedView {
            hosted.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.sm) {
            HStack(spacing: IslandTokens.Space.sm) {
                PixelBitmap(rows: PixelGlyphs.compose, cell: PixelInstrument.cell,
                            gap: PixelInstrument.gap, tone: IslandRamp.step(4))
                Text("Ask Superflow").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                PixelRule(tone: IslandRamp.step(2))
                SurfaceButton("Island settings", action: context.actions.openSettings)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
                    .overlay {
                        PixelBitmap(rows: PixelGlyphs.settings, cell: 1, gap: 0, tone: IslandRamp.step(3))
                            .allowsHitTesting(false)
                    }
            }
            .frame(height: IslandTokens.Size.glyph)
            PixelFlowRail(active: 1)

            context.seam.composeView(content: context.intelligence) { text in
                context.actions.send(text)
            }

            // The draft's own cell trace: an instrument readout of what you are
            // about to send, with the caret marking the next character.
            HStack(spacing: IslandTokens.Space.sm) {
                PixelCaret()
                PixelTextSignal(text: draft, columns: 34)
            }
            Spacer(minLength: 0)
            Text("Right Option to dictate · ⏎ to send")
                .appType(IslandTokens.TypeRole.caption)
                .foregroundStyle(IslandTokens.Color.ink2)
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed()
    }
}

// MARK: listening

/// Live dictation. The pixel meter is the same symmetric cell envelope the
/// notch always drew; the live transcript sits beside it and fades toward the
/// older words. The mark on the left is a pixel cavity, not a boxed icon.
struct ListeningView: View {
    let target: String?
    let context: FlowContext

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: IslandTokens.Space.md) {
                PixelBitmap(rows: PixelGlyphs.listening, cell: PixelInstrument.cell,
                            gap: PixelInstrument.gap, tone: IslandRamp.step(4))
                    .frame(width: IslandTokens.Size.row, alignment: .leading)
                VStack(alignment: .leading, spacing: IslandTokens.Space.xs) {
                    if let target, !target.isEmpty {
                        Text(target).appType(IslandTokens.TypeRole.caption)
                            .foregroundStyle(IslandTokens.Color.ink2)
                            .lineLimit(1)
                    }
                    HStack(spacing: IslandTokens.Space.xs) {
                        Text(context.live.isEmpty ? "Listening" : context.live)
                            .appType(IslandTokens.TypeRole.body)
                            .foregroundStyle(context.live.isEmpty ? IslandTokens.Color.ink2 : IslandTokens.Color.ink)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                        PixelCaret()
                    }
                }
                Spacer(minLength: 0)
                IslandPixelMeter(meter: context.meter, columns: 11)
            }
            .frame(height: IslandTokens.Size.band)
            Spacer(minLength: 0)
            PixelRule(tone: IslandRamp.step(1))
                .padding(.horizontal, IslandTokens.Space.sm)
        }
        .padding(.horizontal, IslandTokens.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: answer

/// The streamed answer. The host still renders the text (selectable Markdown);
/// the Island supplies a pixel readout header, a live data band while streaming
/// and pixel suggestion chips after a meeting.
struct AnswerView: View {
    let text: String
    let streaming: Bool
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack(spacing: IslandTokens.Space.sm) {
                PixelBitmap(rows: PixelGlyphs.answer, cell: PixelInstrument.cell,
                            gap: PixelInstrument.gap, tone: streaming ? IslandRamp.step(4) : IslandRamp.step(3))
                Text(streaming ? "Streaming" : "Answer").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                if streaming {
                    PixelBand(active: true, cells: 16)
                }
                Spacer(minLength: 0)
                IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                           tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            }
            .frame(height: IslandTokens.Size.glyph)
            PixelFlowRail(active: streaming ? 3 : 4)

            if let hosted = context.hostedView {
                hosted
            } else {
                context.seam.answerView(content: answerContent, onCopy: context.actions.copyAnswer)
            }

            // The answer's cell trace sits under the text, so even a short
            // answer has a physical shape on the readout.
            PixelTextSignal(text: text, columns: 40)

            if !context.intelligence.suggestions.isEmpty {
                chips(context.intelligence.suggestions)
            }
            Spacer(minLength: 0)
            PixelRule(tone: IslandRamp.step(1))
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .pixelFramed(tone: IslandRamp.step(2), hot: streaming ? IslandRamp.step(4) : IslandRamp.step(3))
    }

    private var answerContent: IslandIntelligenceContent {
        var content = context.intelligence
        content.answer = text
        content.isStreaming = streaming
        return content
    }

    private func chips(_ suggestions: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: IslandTokens.Space.sm) {
                ForEach(suggestions, id: \.self) { suggestion in
                    PixelChip(title: suggestion) {
                        context.actions.suggestion(suggestion)
                    }
                }
            }
        }
        .frame(height: IslandTokens.Size.control)
    }
}

/// A suggestion rendered as a cell-bordered chip with a leading pixel mark.
/// No capsule background: the registration corners do the framing.
struct PixelChip: View {
    let title: String
    var action: () -> Void

    var body: some View {
        SurfaceButton(title, action: action)
            .frame(height: IslandTokens.Size.control)
            .pixelFramed(tone: IslandRamp.step(2), hot: IslandRamp.step(4))
            .overlay {
                HStack(spacing: IslandTokens.Space.xs) {
                    PixelBitmap(rows: PixelGlyphs.answer, cell: 1, gap: 0, tone: IslandRamp.step(4))
                        .allowsHitTesting(false)
                    Text(title).appType(IslandTokens.TypeRole.caption)
                        .foregroundStyle(IslandTokens.Color.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, IslandTokens.Space.sm)
                .allowsHitTesting(false)
            }
            .accessibilityHint("Ask this follow-up")
    }
}
