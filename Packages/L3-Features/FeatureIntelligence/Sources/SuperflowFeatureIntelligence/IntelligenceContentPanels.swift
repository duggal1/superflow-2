import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI
import SuperflowMeetingIntelligence

/// Settings expands in place: every prompt/theme from `MeetingMode` source is
/// listed, screen context (default on) is toggleable, and no native picker or
/// popover is created — all controls are shared component buttons.
struct IntelligenceSettingsPanel: View {
    @Bindable var model: IntelligenceIslandModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                IntelPixelHeading(glyph: IntelPixel.mark, title: "Prompts", tone: Ramp.blue[4])
                ForEach(model.themes) { theme in
                    AppButton(theme.label,
                              glyph: theme.id == model.selectedThemeID ? .checkmark : nil,
                              kind: theme.id == model.selectedThemeID ? .secondary : .quiet,
                              height: 28) { model.selectTheme(theme) }
                }
                IntelPixelHeading(glyph: IntelPixel.mark, title: "Capture", tone: Ramp.blue[3])
                AppButton("Screen context: \(model.screenAware ? "On" : "Off")",
                          glyph: model.screenAware ? .checkmark : nil,
                          kind: .quiet, height: 28) { model.setScreenAware(!model.screenAware) }
                IntelPixelHeading(glyph: IntelPixel.check, title: "Model", tone: Ramp.blue[3])
                ForEach(ReasoningEffort.allCases, id: \.self) { level in
                    AppButton(level.rawValue.capitalized,
                              glyph: level == model.effort ? .checkmark : nil,
                              kind: level == model.effort ? .secondary : .quiet,
                              height: 28) { model.setEffort(level) }
                }
                AppField("Custom instructions", prompt: "Optional instructions",
                         text: $model.customInstructions, onCard: true,
                         onSubmit: { model.setCustomInstructions(model.customInstructions) })
                IntelPixelHeading(glyph: IntelPixel.lock, title: "Permissions", tone: Ramp.blue[2])
                ForEach(IntelligencePermission.allCases) { permission in
                    permissionRow(permission)
                }
                IntelPixelHeading(glyph: IntelPixel.history, title: "About", tone: Ramp.blue[2])
                aboutRows
            }
        }
        .frame(maxHeight: 240)
        .task { await model.refreshPermissions() }
    }

    private func permissionRow(_ permission: IntelligencePermission) -> some View {
        let status = model.status(for: permission)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                PixelMark(rows: status.isGranted ? IntelPixel.check : IntelPixel.lock,
                          cell: 1, color: status.isGranted ? Ramp.blue[4] : Ramp.blue[2])
                Text(permission.label).appType(.label).foregroundStyle(Tok.text)
                Text(status.label).appType(.caption).foregroundStyle(Tok.text2)
                Spacer(minLength: 0)
                AppButton(status.isGranted ? "Open Settings" : "Fix", glyph: nil,
                          kind: .quiet, height: 24) {
                    Task { await model.fixPermission(permission) }
                }
            }
            Text(permission.rationale).appType(.caption).foregroundStyle(Tok.text2)
        }
    }

    private var aboutRows: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Superflow Intelligence").appType(.label).foregroundStyle(Tok.text)
            Text("Version \(Self.version) (\(Self.build))")
                .appType(.caption).foregroundStyle(Tok.text2)
            Text("Answers stream from Reflection. Screen text is read on this Mac with the Island excluded.")
                .appType(.caption).foregroundStyle(Tok.text2)
        }
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

/// Both surfaces read the same meeting repository. The compact parent owns
/// the scroll container; the app page owns its own scrolling.
struct IntelligenceHistoryPanel: View {
    @Bindable var model: IntelligenceIslandModel
    var compact = true
    @State private var confirmingDelete = false
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                SectionHeader("Meeting history")
                Spacer()
                if model.isLoadingHistory {
                    Text("Loading…").appType(.caption).foregroundStyle(Tok.text2)
                }
                AppButton("Refresh", glyph: .refresh, kind: .quiet, height: ControlHeight.small) {
                    Task { await model.loadHistory(query: model.historyQuery) }
                }
            }
            if compact {
                AppField("Search meetings", prompt: "Search meeting transcripts",
                         text: $model.historyQuery, onCard: true,
                         onSubmit: { Task { await model.loadHistory(query: model.historyQuery) } })
            }
            if let error = model.historyError {
                Text(error).appType(.caption).foregroundStyle(Tok.text2)
            }
            if let item = model.selectedHistory {
                HStack {
                    AppButton("Back", glyph: .chevronLeft, kind: .quiet, height: ControlHeight.small) {
                        confirmingDelete = false
                        deleteError = nil
                        model.closeHistory()
                    }
                    Spacer()
                    AppButton("Copy transcript", glyph: .copy, kind: .secondary, height: ControlHeight.small) {
                        Task { await model.copyHistoryItem(item.id) }
                    }
                }
                if confirmingDelete {
                    HStack {
                        Text("Delete this meeting transcript?").appType(.caption)
                        Spacer()
                        AppButton("Cancel", kind: .quiet, height: ControlHeight.small) {
                            confirmingDelete = false
                        }
                        AppButton("Delete", glyph: .delete, kind: .secondary, height: ControlHeight.small) {
                            confirmingDelete = false
                            Task {
                                do { try await model.deleteHistoryItem(item.id) }
                                catch { deleteError = error.localizedDescription }
                            }
                        }
                    }
                } else {
                    AppButton("Delete transcript", glyph: .delete, kind: .quiet, height: ControlHeight.small) {
                        confirmingDelete = true
                    }
                }
                if let deleteError {
                    Text(deleteError).appType(.caption).foregroundStyle(Tok.text2)
                }
                Text(item.title).appType(.title)
                Text(item.fullText.isEmpty ? "No transcript was saved." : item.fullText)
                    .appType(.reading).foregroundStyle(Tok.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(item.answers.enumerated()), id: \.offset) { _, answer in
                    MarkdownAnswer(text: answer)
                }
            } else if model.history.isEmpty {
                Text(model.isLoadingHistory ? "Loading meetings…" :
                     model.historyQuery.isEmpty ? "No meetings saved yet." : "No matching meetings.")
                    .appType(.body).foregroundStyle(Tok.text2)
                    .padding(.vertical, Space.sm)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.history) { item in
                        IntelligenceMeetingRow(item: item) {
                            Task { await model.openHistoryItem(item.id) }
                        }
                    }
                }
            }
        }
    }
}

struct IntelligenceMeetingRow: View {
    let item: IntelligenceHistoryItem
    let open: () -> Void

    var body: some View {
        RowButton(item.title, height: 56, action: open) {
            HStack(spacing: Space.sm) {
                IconView(.meetings, size: 14, tint: Tok.text2)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(item.title).appType(.label).foregroundStyle(Tok.text).lineLimit(1)
                    HStack(spacing: Space.xs) {
                        TimelineView(.everyMinute) { clock in
                            Text(Humanize.when(item.date, now: clock.date))
                        }
                        Text(Humanize.words(item.wordCount)).monospacedDigit()
                    }
                    .appType(.caption).foregroundStyle(Tok.text2)
                }
                Spacer(minLength: 0)
                IconView(.chevronRight, size: 12, tint: Tok.text2)
            }
        }
    }
}
