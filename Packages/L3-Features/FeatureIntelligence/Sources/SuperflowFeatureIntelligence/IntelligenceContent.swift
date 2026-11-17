import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// The one SwiftUI surface Agent 1 hosts in the Island's compose / answer /
/// settings / history / suggestions states. It renders only what the injected
/// model exposes; it owns no network, database or keychain access.
public struct IntelligenceContent: View {
    @Bindable public var model: IntelligenceIslandModel

    public init(model: IntelligenceIslandModel) { _model = Bindable(model) }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            header
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
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            IconView(.intelligence, size: 14, tint: Tok.text2)
            Text("Intelligence").appType(.label).foregroundStyle(Tok.text)
            Spacer(minLength: 0)
            AppButton(model.settingsExpanded ? "Done" : "Settings", glyph: .settings,
                      kind: .quiet, height: 24) { model.toggleSettings() }
        }
        .frame(height: ControlHeight.regular)
    }

    private var compose: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            AppField("Question", prompt: "Enter any data and press Enter",
                     text: $model.input, onCard: true) {
                Task { await model.submit() }
            }
            if let question = model.pendingDetectedQuestion {
                AppButton("Answer: \(question)", glyph: .arrow, kind: .secondary, height: 28) {
                    Task { await model.askDetectedQuestion() }
                }
            }
            Text("Screen context is \(model.screenAware ? "on" : "off"). Answers stream here.")
                .appType(.caption).foregroundStyle(Tok.text2)
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if model.phase == .thinking {
                Text("Thinking…").appType(.caption).foregroundStyle(Tok.text2)
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
                AppButton("Copy", glyph: .copy, kind: .primary, height: 24) {
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
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Suggested next questions").appType(.caption).foregroundStyle(Tok.text2)
            ForEach(model.suggestions, id: \.self) { question in
                AppButton(question, glyph: .arrow, kind: .quiet, height: 28) {
                    Task { await model.askSuggestion(question) }
                }
            }
        }
    }
}
