import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// The one SwiftUI surface hosted in the Island's compose / answer / settings /
/// history / suggestions states. It renders only what the injected model
/// exposes; it owns no network, database or keychain access. Its visual
/// language is the Island's: cell glyphs, dotted rules and live bands.
public struct IntelligenceContent: View {
    @Bindable public var model: IntelligenceIslandModel

    public init(model: IntelligenceIslandModel) { _model = Bindable(model) }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            header
            IntelPixelRule(tone: Ramp.blue[1])
            switch model.slot {
            case .compose: compose
            case .answer: answer
            case .settings: IntelligenceSettingsPanel(model: model)
            case .history: IntelligenceHistoryPanel(model: model)
            case .suggestions: suggestions
            }
        }
        .padding(Space.md)
        .appType(.body)
        .foregroundStyle(Tok.text)
        .intelPixelFramed()
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            PixelMark(rows: IntelPixel.mark, cell: IntelPixel.cell, color: Ramp.blue[4])
            Text("Intelligence").appType(.label).foregroundStyle(Tok.text)
            IntelPixelRule(tone: Ramp.blue[2])
            AppButton(model.settingsExpanded ? "Done" : "Settings", glyph: .settings,
                      kind: .quiet, height: 24) { model.toggleSettings() }
        }
        .frame(height: ControlHeight.regular)
    }

    private var compose: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            IntelPixelHeading(glyph: IntelPixel.send, title: "Compose", tone: Ramp.blue[4])
            HStack(spacing: Space.xs) {
                AppField("Question", prompt: "Enter any data and press Enter",
                         text: $model.input, onCard: true) {
                    Task { await model.submit() }
                }
                PixelMark(rows: IntelPixel.send, cell: IntelPixel.cell,
                          color: model.input.isEmpty ? Ramp.blue[2] : Ramp.blue[4])
            }
            if let question = model.pendingDetectedQuestion {
                AppButton("Answer: \(question)", glyph: .arrow, kind: .secondary, height: 28) {
                    Task { await model.askDetectedQuestion() }
                }
            }
            HStack(spacing: Space.sm) {
                PixelMark(rows: IntelPixel.mark, cell: 1,
                          color: model.screenAware ? Ramp.blue[4] : Ramp.blue[2])
                Text("Screen context is \(model.screenAware ? "on" : "off"). Answers stream here.")
                    .appType(.caption).foregroundStyle(Tok.text2)
            }
            IntelPixelRule(tone: Ramp.blue[1])
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            IntelPixelHeading(glyph: IntelPixel.mark, title: "Answer",
                              tone: model.phase == .thinking ? Ramp.blue[3] : Ramp.blue[4])
            if model.phase == .thinking {
                HStack(spacing: Space.sm) {
                    IntelPixelBand(active: true, cells: 16)
                    Text("Thinking").appType(.caption).foregroundStyle(Tok.text2)
                }
            } else if case .failed(let message) = model.phase {
                Text(message).appType(.reading).foregroundStyle(Tok.text2)
                    .textSelection(.enabled)
            } else {
                ScrollView {
                    if model.answer.isEmpty {
                        Text("No answer yet.")
                            .appType(.reading)
                            .foregroundStyle(Tok.text)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        MarkdownAnswer(text: model.answer)
                    }
                }
                .frame(maxHeight: 160)
                .padding(Space.sm)
                .background(Tok.well, in: .rect(cornerRadius: Radius.nested, style: .continuous))
            }
            HStack(spacing: Space.xs) {
                PixelMark(rows: IntelPixel.check, cell: IntelPixel.cell, color: Ramp.blue[4])
                AppButton("Copy", glyph: nil, kind: .primary, height: 24) {
                    Task { await model.copy() }
                }
                if model.phase == .done || model.phase == .truncated {
                    AppButton("Go deeper", glyph: nil, kind: .secondary, height: 24) { model.goDeeper() }
                }
                if case .failed = model.phase {
                    AppButton("Retry", glyph: .refresh, kind: .secondary, height: 24) { model.retry() }
                }
                Spacer(minLength: 0)
                AppButton("Ask another", glyph: nil, kind: .quiet, height: 24) { model.cancel() }
            }
            IntelPixelRule(tone: Ramp.blue[1])
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            IntelPixelHeading(glyph: IntelPixel.send, title: "Suggested next questions",
                              tone: Ramp.blue[4])
            ForEach(model.suggestions, id: \.self) { question in
                HStack(spacing: Space.sm) {
                    PixelMark(rows: IntelPixel.send, cell: 1, color: Ramp.blue[3])
                    AppButton(question, glyph: nil, kind: .quiet, height: 28) {
                        Task { await model.askSuggestion(question) }
                    }
                }
            }
            IntelPixelRule(tone: Ramp.blue[1])
        }
    }
}
