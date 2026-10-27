import AppKit
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

public struct MeetingsView: View {
    @ObservedObject private var model: MeetingsViewModel
    @State private var searchFocus = false

    public init(model: MeetingsViewModel) {
        self.model = model
    }

    public var body: some View {
        Page(title: "Meetings") {
            HStack(spacing: Space.sm) {
                Segmented(selection: $model.tab, items: [
                    Segmented.Item(MeetingsTab.live.label, value: MeetingsTab.live),
                    Segmented.Item(MeetingsTab.past.label, value: MeetingsTab.past),
                ])
                if model.tab == .past {
                    SearchField(text: $model.pastQuery, prompt: "Search meetings",
                                isFocused: $searchFocus)
                }
            }
        } trailing: {
            if model.tab == .past {
                ActionMenu(actions: [
                    .init("Export Markdown…") {
                        export(model.markdownExport(), name: "meeting.md", type: .plainText)
                    },
                    .init("Export JSON…") {
                        export(model.jsonExport(), name: "meeting.json", type: .json)
                    },
                ])
                AppButton("Copy Markdown", glyph: .copy, kind: .primary,
                          height: Layout.control, enabled: model.selectedDocument != nil) {
                    Task { await model.copySelected() }
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: Space.md) {
                if model.tab == .past, let error = model.error {
                    NoticeBanner(error, tone: .rose, actionTitle: "Reload") {
                        Task { await model.loadPast() }
                    }
                }
                switch model.tab {
                case .live:
                    live
                case .past:
                    MeetingPastView(model: model)
                }
            }
        }
        .searchShortcut($searchFocus)
        .task {
            await model.observe()
            await model.loadPast()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                model.tick()
            }
        }
        .onChange(of: model.pastQuery) { _, _ in
            guard model.tab == .past else { return }
            Task { await model.loadPast() }
        }
        .toast(model.toast)
    }

    @ViewBuilder
    private var live: some View {
        if model.isActive {
            running
        } else {
            VStack(spacing: Space.md) {
                PixelStop(cells: 11, cell: 4)
                Text("Meetings start with a hold.")
                    .font(Typography.displayFont(size: TypeScale.displaySSize))
                    .tracking(TypeScale.displaySTracking)
                    .foregroundStyle(Tok.text)
                HStack(spacing: Space.xs) {
                    Text("Hold")
                        .font(Typography.body)
                        .foregroundStyle(Tok.text2)
                    KeyCap("⌘")
                    Text("right")
                        .font(Typography.body)
                        .foregroundStyle(Tok.text2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xxxl)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hold the right Command key to start a meeting.")
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(spacing: Space.xs) {
                        DotView(model.statusTone)
                        Text(model.statusLabel)
                            .font(Typography.headline)
                            .foregroundStyle(Tok.text)
                        Text(model.elapsedLabel)
                            .font(Typography.secondary)
                            .monospacedDigit()
                            .foregroundStyle(Tok.text2)
                        Spacer(minLength: Space.md)
                        AppButton("Stop", kind: .primary, height: ControlHeight.small) {
                            Task { _ = await model.stop() }
                        }
                        AppButton("Cancel", kind: .quiet, height: ControlHeight.small) {
                            Task { await model.cancel() }
                        }
                    }
                    stream(title: "You", levels: model.micLevels, text: model.micPartial,
                           words: model.micWordCount)
                    stream(title: "Remote", levels: model.systemLevels, text: model.systemPartial,
                           words: model.systemWordCount)
                }
            }
            if let notice = model.notice {
                NoticeBanner(notice, tone: .orange)
            }
        }
    }

    private func stream(title: String, levels: [Float], text: String, words: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text(title)
                    .font(Typography.secondaryMedium)
                    .foregroundStyle(Tok.text2)
                Spacer(minLength: Space.sm)
                Text("\(words.formatted()) words")
                    .font(Typography.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
            }
            LevelsWaveform(levels: levels, barWidth: 2, spacing: 2)
                .frame(height: 24)
            Text(text.isEmpty ? "Listening…" : text)
                .font(Typography.large)
                .foregroundStyle(text.isEmpty ? Tok.text2 : Tok.text)
                .lineLimit(3)
                .frame(maxWidth: Space.proseMaxWidth, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func export(_ data: Data?, name: String, type: UTType) {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            model.toast.show("Meeting exported.", style: .success)
        } catch {
            model.toast.show("Could not write the file. \(error.localizedDescription)", style: .error)
        }
    }
}
