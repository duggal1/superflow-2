import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

// MARK: compose

/// A typed question. The Intelligence host owns the field and the send glyph;
/// the Island only supplies the target and settings affordances around it.
struct ComposeView: View {
    let draft: String
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            header(title: "Ask Superflow")
            if let hosted = context.hostedView {
                hosted
            } else {
                context.seam.composeView(content: context.intelligence) { text in
                    context.actions.send(text)
                }
            }
            Spacer(minLength: 0)
            hint("Right Option to dictate · ⏎ to send")
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(title: String) -> some View {
        HStack(spacing: IslandTokens.Space.sm) {
            IconView(.intelligence, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.ink)
            Text(title).appType(IslandTokens.TypeRole.label)
                .foregroundStyle(IslandTokens.Color.ink)
            Spacer(minLength: 0)
            IconButton(.settings, label: "Island settings", size: IslandTokens.Size.glyph,
                       tint: IslandTokens.Color.ink2, action: context.actions.openSettings)
                .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).appType(IslandTokens.TypeRole.caption)
            .foregroundStyle(IslandTokens.Color.ink2)
    }
}

// MARK: listening

/// Live dictation. The pixel waveform is the existing renderer, reused as-is:
/// the same symmetric 11-column meter the pre-rebuild Island drew. The live
/// transcript sits beside the caret and fades toward the older words.
struct ListeningView: View {
    let target: String?
    let context: FlowContext

    var body: some View {
        HStack(spacing: IslandTokens.Space.md) {
            IconView(.mic, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.ink)
                .frame(width: IslandTokens.Size.row, alignment: .leading)
            VStack(alignment: .leading, spacing: IslandTokens.Space.xs) {
                if let target, !target.isEmpty {
                    Text(target).appType(IslandTokens.TypeRole.caption)
                        .foregroundStyle(IslandTokens.Color.ink2)
                        .lineLimit(1)
                }
                Text(context.live.isEmpty ? "Listening…" : context.live)
                    .appType(IslandTokens.TypeRole.body)
                    .foregroundStyle(context.live.isEmpty ? IslandTokens.Color.ink2 : IslandTokens.Color.ink)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            IslandPixelMeter(meter: context.meter, columns: 11)
        }
        .padding(.horizontal, IslandTokens.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: answer

/// The streamed answer, presented by the Intelligence host, with the fixed-width
/// Copy control and any follow-up chips from a finished meeting.
struct AnswerView: View {
    let text: String
    let streaming: Bool
    let context: FlowContext

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.md) {
            HStack(spacing: IslandTokens.Space.sm) {
                IconView(.intelligence, size: IslandTokens.Size.glyph, tint: IslandTokens.Color.ink)
                Text(streaming ? "Answering" : "Answer").appType(IslandTokens.TypeRole.label)
                    .foregroundStyle(IslandTokens.Color.ink)
                Spacer(minLength: 0)
                IconButton(.close, label: "Dismiss", size: IslandTokens.Size.glyph,
                           tint: IslandTokens.Color.ink2, action: context.actions.dismiss)
                    .frame(width: IslandTokens.Size.row, height: IslandTokens.Size.row)
            }

            if let hosted = context.hostedView {
                hosted
            } else {
                context.seam.answerView(content: answerContent, onCopy: context.actions.copyAnswer)
            }

            if !context.intelligence.suggestions.isEmpty {
                chips(context.intelligence.suggestions)
            }
            Spacer(minLength: 0)
        }
        .padding(IslandTokens.Size.cardPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    AppButton(suggestion, kind: .secondary,
                              height: IslandTokens.Size.control) {
                        context.actions.suggestion(suggestion)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(height: IslandTokens.Size.control)
    }
}
