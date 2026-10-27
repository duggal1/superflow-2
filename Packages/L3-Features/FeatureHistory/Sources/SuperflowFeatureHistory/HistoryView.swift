import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

/// A reading room, not a table: a grouped list in the 320pt pane and a transcript
/// pane you can read, copy and compare against the raw text.
public struct HistoryView: View {
    @ObservedObject private var model: HistoryViewModel
    @State private var today = LocalDay.string(for: Date())
    @State private var searchFocus = false
    @FocusState private var listFocus: Bool

    public init(model: HistoryViewModel) {
        self.model = model
    }

    public var body: some View {
        SplitPage(title: "History") {
            SearchField(text: $model.query, prompt: "Search transcripts", isFocused: $searchFocus)
        } trailing: {
            BarIconButton(glyph: .copy, label: "Copy transcript") {
                Task { await model.copySelected() }
            }
            .disabled(model.selectedID == nil)
            BarIconButton(glyph: .delete, label: "Delete session") {
                Task { await model.deleteSelected() }
            }
            .disabled(model.selectedID == nil)
        } list: {
            listPane
                .padding(.leading, Space.lg)
                .padding(.trailing, Space.md)
        } detail: {
            detailPane
                .padding(.trailing, Layout.pad)
                .padding(.top, Space.xs)
        }
        .searchShortcut($searchFocus)
        .task { await model.load() }
        .onChange(of: model.query) { _, _ in
            Task { await model.load() }
        }
        .onKeyPress(.delete) {
            Task { await model.deleteSelected() }
            return .handled
        }
        .toast(model.toast)
    }

    // MARK: list

    private var groups: [HistoryGrouping.Day] {
        HistoryGrouping.days(model.sessions, today: today)
    }

    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var listPane: some View {
        if model.isLoading && model.sessions.isEmpty {
            Text("Reading your library…")
                .font(Typography.body)
                .foregroundStyle(Tok.text2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Space.xl)
        } else if model.isEmpty && !trimmedQuery.isEmpty {
            EmptyState("No sessions match.",
                       message: "Try another word, or clear the search.",
                       density: .pane)
        } else if model.isEmpty {
            EmptyState("Nothing dictated yet.",
                       message: "Hold fn, speak, then release. Sessions land here.",
                       density: .pane)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.sessions) { session in
                                row(session)
                            }
                        } header: {
                            Text(HistoryGrouping.label(for: group.day, today: today))
                                .font(Typography.secondary)
                                .foregroundStyle(Tok.text2)
                                .padding(.horizontal, Space.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Space.xxs)
                                .background(Tok.bg)
                        }
                    }
                    if model.hasMore {
                        AppButton("Load older sessions", kind: .quiet) {
                            Task { await model.loadMore() }
                        }
                        .padding(.horizontal, Space.xs)
                    }
                }
            }
            .scrollEdgeSoft()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func row(_ session: SessionRecord) -> some View {
        RowButton(session.displayTitle, height: 56, selected: session.id == model.selectedID) {
            Task { await model.select(session.id) }
        } content: {
            HStack(alignment: .center, spacing: Space.sm) {
                appIcon(session)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.xs) {
                        Text(session.displayTitle)
                            .font(Typography.body)
                            .foregroundStyle(Tok.text)
                            .lineLimit(2)
                        if session.kind == .meeting {
                            Badge("Meeting", variant: .violet, size: .sm)
                        }
                    }
                    HStack(spacing: Space.xxs) {
                        Text(HistoryGrouping.timeLabel(session.startedAt))
                            .font(Typography.secondary)
                            .foregroundStyle(Tok.text2)
                        Spacer(minLength: Space.xs)
                        Text("\(session.wordCount.formatted()) words")
                            .font(Typography.secondary)
                            .monospacedDigit()
                            .foregroundStyle(Tok.text2)
                    }
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }

    @ViewBuilder
    private func appIcon(_ session: SessionRecord) -> some View {
        if let image = AppInfo.icon(for: session.frontmostBundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            Icon(.waveform, size: 14, tint: Tok.text2)
                .frame(width: 20, height: 20)
        }
    }

    // MARK: detail

    @ViewBuilder
    private var detailPane: some View {
        if let session = model.selectedSession {
            VStack(alignment: .leading, spacing: Space.md) {
                header(session)
                Segmented(selection: $model.showRaw, items: [
                    Segmented.Item("Cleaned", value: false),
                    Segmented.Item("Raw", value: true),
                ])
                transcript
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: Space.sm) {
                PixelStop(cells: 11, cell: 3)
                Text("Select a session.")
                    .font(Typography.headline)
                    .foregroundStyle(Tok.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ session: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(AppInfo.name(for: session.frontmostBundleID))
                .font(Typography.headline)
                .foregroundStyle(Tok.text)
            HStack(spacing: Space.sm) {
                Text(HistoryGrouping.timeLabel(session.startedAt))
                    .monospacedDigit()
                Text(session.durationLabel)
                    .monospacedDigit()
                Spacer(minLength: Space.md)
                Text("\(session.wordCount.formatted()) words")
                    .monospacedDigit()
            }
            .font(Typography.secondary)
            .foregroundStyle(Tok.text2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(model.segments) { segment in
                    segmentView(segment)
                }
            }
            .frame(maxWidth: Space.proseMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Space.lg)
        }
        .scrollEdgeSoft()
    }

    private func segmentView(_ segment: Segment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let speaker = model.speakerName(for: segment) {
                Text(speaker)
                    .font(Typography.secondaryMedium)
                    .foregroundStyle(Tok.text2)
            }
            if model.showRaw {
                Text(rawText(segment))
            } else {
                Text(model.displayText(for: segment))
                    .font(Typography.large)
                    .foregroundStyle(Tok.text)
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Raw mode marks the words cleanup changed, so the difference is visible.
    private func rawText(_ segment: Segment) -> AttributedString {
        var attributed = AttributedString()
        let pieces = TextDiff.segments(reference: segment.bestText, candidate: segment.rawText)
        for piece in pieces {
            var run = AttributedString(piece.text)
            run.font = Typography.large
            run.foregroundColor = piece.changed ? Tok.text : Tok.text2
            if piece.changed { run.backgroundColor = Tok.accentSoft }
            attributed += run
        }
        return attributed
    }
}
