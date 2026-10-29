import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

/// A reading room, not a table: a grouped list in the 320pt pane and a transcript
/// pane you can read, copy and compare against the raw text.
public struct HistoryView: View {
    @ObservedObject private var model: HistoryViewModel
    @State private var searchFocus = false

    public init(model: HistoryViewModel) {
        self.model = model
    }

    public var body: some View {
        SplitPage(title: "History") {
            SearchField(text: $model.query, prompt: "Search transcripts", isFocused: $searchFocus)
        } trailing: {
            EmptyView()
        } list: {
            listPane
                .padding(.leading, 20)
                .padding(.trailing, Space.md)
        } detail: {
            detailPane
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
        HistoryGrouping.days(model.sessions)
    }

    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var listPane: some View {
        if model.isLoading && model.sessions.isEmpty {
            Text("Reading your library…")
                .appType(.body)
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
                            Text(HistoryGrouping.label(for: group.day))
                                .appType(.caption)
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
        RowButton(title(for: session), height: 56, selected: session.id == model.selectedID) {
            Task { await model.select(session.id) }
        } content: {
            HStack(spacing: 12) {
                appIcon(session)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.wordCount == 0 ? "No speech" : title(for: session))
                        .appType(.label)
                        .foregroundStyle(session.wordCount == 0 ? Tok.text2 : Tok.text)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        TimelineView(.everyMinute) { context in
                            Text(Humanize.when(session.startedAt, now: context.date))
                        }
                        Spacer(minLength: 8)
                        if session.wordCount > 0 {
                            Text(Humanize.words(session.wordCount)).monospacedDigit()
                        }
                    }
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
                }
            }
            .padding(.horizontal, 12)
        }
        .pixelAudit("HistoryRow")
    }

    private func title(for session: SessionRecord) -> String {
        if let preview = session.preview, !preview.isEmpty { return preview }
        if let title = session.title, !title.isEmpty { return title }
        return "No speech"
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
            IconView(.waveform, size: 14, tint: Tok.text2)
                .frame(width: 20, height: 20)
        }
    }

    // MARK: detail

    @ViewBuilder
    private var detailPane: some View {
        if let session = model.selectedSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HistoryDetailHeader(session: session,
                                        appName: AppInfo.name(for: session.frontmostBundleID),
                                        onCopy: { Task { await model.copySelected() } },
                                        onDelete: { Task { await model.deleteSelected() } })
                    if let audio = audioURL(for: session) {
                        AudioPreview(url: audio)
                            .id(session.id)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Segmented(selection: $model.showRaw, items: [
                            Segmented.Item("Cleaned", value: false),
                            Segmented.Item("Raw", value: true),
                        ])
                        transcript
                    }
                }
                .padding(.horizontal, Layout.pad)
                .padding(.top, Space.xxs)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeSoft()
        } else {
            VStack(spacing: Space.sm) {
                PixelStop(cells: 11, cell: 3)
                Text("Select a session.")
                    .appType(.title)
                    .foregroundStyle(Tok.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The file is the source of truth. Peaks and duration stay in the archive
    /// for retention; the spectrogram is computed from the audio itself.
    private func audioURL(for session: SessionRecord) -> URL? {
        let url = AudioArchiveLocation.url(for: session.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    @ViewBuilder
    private var transcript: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(model.segments) { segment in
                segmentView(segment)
            }
        }
        .frame(maxWidth: Space.proseMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func segmentView(_ segment: Segment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let speaker = model.speakerName(for: segment) {
                Text(speaker)
                    .appType(.label)
                    .foregroundStyle(Tok.text2)
            }
            if model.showRaw {
                Text(rawText(segment))
            } else {
                Text(model.displayText(for: segment))
                    .appType(.reading)
                    .foregroundStyle(Tok.text)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Raw mode marks the words cleanup changed, so the difference is visible.
    private func rawText(_ segment: Segment) -> AttributedString {
        var attributed = AttributedString()
        let pieces = TextDiff.segments(reference: segment.bestText, candidate: segment.rawText)
        for piece in pieces {
            var run = AttributedString(piece.text)
            run.font = AppType.reading.font
            run.foregroundColor = piece.changed ? Tok.text : Tok.text2
            if piece.changed { run.backgroundColor = Tok.accentSoft }
            attributed += run
        }
        return attributed
    }
}

/// Actions live next to the thing they act on: Copy and Delete sit on the
/// session's own header row, and the glyph (not its hit target) lands on the
/// content edge.
struct HistoryDetailHeader: View {
    let session: SessionRecord
    let appName: String
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if let image = AppInfo.icon(for: session.frontmostBundleID) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                } else {
                    IconView(.waveform, size: 14, tint: Tok.text2)
                        .frame(width: 20, height: 20)
                }
                Text(appName)
                    .appType(.title)
                    .foregroundStyle(Tok.text)
                Spacer(minLength: 16)
                HStack(spacing: 4) {
                    CopyButton(action: onCopy)
                    BarIconButton(glyph: .delete, label: "Delete session", action: onDelete)
                }
                // A 32pt hit target around a 16pt glyph: pull it out by 8 so the
                // glyph sits on the content edge (law 4).
                .padding(.trailing, -8)
            }
            .frame(height: 32)

            HStack(spacing: 12) {
                TimelineView(.everyMinute) { context in
                    Text(Humanize.when(session.startedAt, now: context.date))
                }
                Text(Humanize.duration(TimeInterval(session.durationMs) / 1000))
                Text(Humanize.words(session.wordCount)).monospacedDigit()
            }
            .appType(.caption)
            .foregroundStyle(Tok.text2)
            .padding(.leading, 32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .pixelAudit("HistoryDetailHeader")
    }
}

/// Copy confirms in place: the glyph morphs to a checkmark for 1.2 s.
struct CopyButton: View {
    let action: () -> Void
    @State private var done = false

    var body: some View {
        BarIconButton(glyph: done ? .checkmark : .copy, label: "Copy transcript") {
            action()
            done = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                done = false
            }
        }
        .animation(.snappy(duration: 0.2), value: done)
    }
}
