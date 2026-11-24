import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Shared, model-backed workspace. The compact variant is mounted directly
/// inside the black Island; the window variant owns no second answer service.
public struct IntelligenceContent: View {
    @Bindable public var model: IntelligenceIslandModel
    private let compact: Bool
    private let recording: Bool
    private let onRecord: (() -> Void)?
    private let onDismiss: (() -> Void)?
    private let onConfiguration: (() -> Void)?
    @State private var panel: Panel = .ask
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Panel { case ask, history, settings }

    public init(model: IntelligenceIslandModel, compact: Bool = true,
                recording: Bool = false, onRecord: (() -> Void)? = nil,
                onDismiss: (() -> Void)? = nil, onConfiguration: (() -> Void)? = nil) {
        _model = Bindable(model)
        self.compact = compact
        self.recording = recording
        self.onRecord = onRecord
        self.onDismiss = onDismiss
        self.onConfiguration = onConfiguration
    }

    public var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Space.xs) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            switch panel {
                            case .ask: askSurface
                            case .history: IntelligenceHistoryPanel(model: model, compact: true)
                            case .settings:
                                IntelligenceSettingsPanel(model: model)
                                if let onConfiguration {
                                    AppButton("Open app", glyph: .externalLink, kind: .secondary, action: onConfiguration)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, Space.cardPadding)
                .padding(.vertical, Space.sm)
                .background(Tok.island)
                .environment(\.colorScheme, .dark)
                .onExitCommand { onDismiss?() }
            } else {
                VStack(alignment: .leading, spacing: Space.sectionGap) {
                    askSurface
                    IntelligenceHistoryPanel(model: model, compact: false)
                }
            }
        }
        .foregroundStyle(Tok.text)
        .task { await model.loadHistory(query: model.historyQuery) }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            PixelMark(rows: IntelPixel.mark, cell: IntelPixel.cell, color: Ramp.blue[4])
            Text("Intelligence").appType(.label)
            Spacer(minLength: 0)
            tab(.ask, "Ask", glyph: .intelligence)
            tab(.history, "History", glyph: .history)
            tab(.settings, "Settings", glyph: .settings)
            if let onDismiss {
                IconButton(.close, label: "Close Intelligence", size: 14, action: onDismiss)
            }
        }
        .frame(height: ControlHeight.large)
    }

    private func tab(_ value: Panel, _ label: String, glyph: Icon) -> some View {
        IconButton(glyph, label: label, size: 14,
                   tint: panel == value ? Tok.accentText : Tok.text2) {
            withAnimation(reduceMotion ? nil : Motion.fade) { panel = value }
        }
        .accessibilityAddTraits(panel == value ? .isSelected : [])
    }

    private var askSurface: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    PixelMark(rows: IntelPixel.send, cell: IntelPixel.cell, color: Ramp.blue[4])
                    Text("Ask me about anything.").appType(.title)
                    Spacer(minLength: 0)
                    if recording {
                        Text("Recording").appType(.caption).foregroundStyle(Tok.accentText)
                    }
                }
                HStack(spacing: Space.xs) {
                    AppField("Question", prompt: "Ask me about anything", text: $model.input, onCard: true) {
                        submit()
                    }
                    AppButton("Ask", glyph: .arrowUp, kind: .primary, height: ControlHeight.regular,
                              enabled: !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        submit()
                    }
                }
                modeRail
                HStack(spacing: Space.xxs) {
                    if let onRecord {
                        AppButton(recording ? "Stop recording" : "Record meeting",
                                  glyph: recording ? .stop : .mic,
                                  kind: .secondary, height: ControlHeight.small, action: onRecord)
                    }
                    AppButton(model.screenAware ? "Screen on" : "Screen off",
                              glyph: model.screenAware ? .checkmark : .eyeSlash,
                              kind: .quiet, height: ControlHeight.small) {
                        model.setScreenAware(!model.screenAware)
                    }
                    Spacer(minLength: 0)
                    if compact {
                        Text("Right ⌥ · Left ⌃").appType(.caption).foregroundStyle(Tok.text2)
                            .lineLimit(1)
                    }
                }
                if !compact {
                    Text("Right Option to ask by voice · Left Control to start or stop a meeting")
                        .appType(.caption).foregroundStyle(Tok.text2)
                }
            }
            .padding(compact ? Space.xs : Space.cardPadding)
            .background(Tok.surface, in: .rect(cornerRadius: Radius.nested))
            if let question = model.pendingDetectedQuestion {
                AppButton("Answer detected question", glyph: .arrow, kind: .secondary) {
                    Task { await model.askDetectedQuestion() }
                }
                Text(question).appType(.caption).foregroundStyle(Tok.text2).lineLimit(2)
            }
            if model.phase != .idle { answerSurface }
            if !model.suggestions.isEmpty {
                SectionHeader("Follow-up questions")
                ForEach(model.suggestions, id: \.self) { question in
                    RowButton(question, height: ControlHeight.large) {
                        Task { await model.askSuggestion(question) }
                    } content: {
                        HStack(spacing: Space.xs) {
                            IconView(.arrow, size: 14, tint: Tok.accentText)
                            Text(question).appType(.body).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            if compact && model.phase == .idle {
                HStack {
                    Text("Recent meetings").appType(.label)
                    Spacer()
                    AppButton("View all", glyph: .chevronRight, kind: .quiet, height: ControlHeight.small) {
                        panel = .history
                    }
                }
                if model.history.isEmpty {
                    Text(model.isLoadingHistory ? "Loading meetings…" : "No meetings saved yet.")
                        .appType(.caption).foregroundStyle(Tok.text2)
                } else {
                    ForEach(Array(model.history.prefix(2))) { item in
                        IntelligenceMeetingRow(item: item) {
                            panel = .history
                            Task { await model.openHistoryItem(item.id) }
                        }
                    }
                }
            }
        }
    }

    private var modeRail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.xxs) {
                ForEach(model.themes) { theme in
                    AppButton(theme.label, glyph: modeIcon(theme.id),
                              kind: theme.id == model.selectedThemeID ? .secondary : .quiet,
                              height: ControlHeight.small) {
                        model.selectTheme(theme)
                    }
                    .accessibilityAddTraits(theme.id == model.selectedThemeID ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Prompt mode")
    }

    private func modeIcon(_ id: String) -> Icon {
        switch id {
        case "normal": .meetings
        case "codingInterview": .code
        case "sales": .chart
        case "journal": .dictionary
        default: .settings
        }
    }

    private var answerSurface: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                PixelMark(rows: IntelPixel.mark, cell: IntelPixel.cell, color: Ramp.blue[4])
                Text(answerTitle).appType(.label)
                Spacer(minLength: 0)
                if model.phase == .thinking || model.phase == .streaming {
                    IntelPixelBand(active: !reduceMotion, cells: 12)
                    AppButton("Stop", glyph: .stop, kind: .quiet, height: ControlHeight.small) {
                        model.cancel()
                    }
                } else {
                    AppButton("Copy", glyph: .copy, kind: .secondary, height: ControlHeight.small,
                              enabled: !model.answer.isEmpty) {
                        Task { await model.copy() }
                    }
                }
            }
            if case .failed(let message) = model.phase {
                Text(message).appType(.body).foregroundStyle(Tok.text2).textSelection(.enabled)
                AppButton("Retry", glyph: .refresh, kind: .secondary) { model.retry() }
            } else if !model.answer.isEmpty {
                MarkdownAnswer(text: model.answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Preparing your answer…").appType(.body).foregroundStyle(Tok.text2)
            }
            if model.phase == .done || model.phase == .truncated {
                AppButton("Go deeper", kind: .quiet, height: ControlHeight.small) { model.goDeeper() }
            }
        }
        .padding(compact ? Space.xs : Space.cardPadding)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.nested))
    }

    private var answerTitle: String {
        switch model.phase {
        case .thinking: "Thinking"
        case .streaming: "Answering"
        case .truncated: "Answer · incomplete"
        case .failed: "Could not answer"
        default: "Answer"
        }
    }

    private func submit() {
        Task { await model.submit() }
    }
}
