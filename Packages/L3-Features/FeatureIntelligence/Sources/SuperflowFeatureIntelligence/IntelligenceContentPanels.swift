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

/// Island history: list, search, open full transcript + stored answers,
/// delete and copy. All reads/writes go through the injected history seam.
struct IntelligenceHistoryPanel: View {
    @Bindable var model: IntelligenceIslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            AppField("Search history", prompt: "Search transcripts",
                     text: $model.historyQuery, onCard: true) {
                Task { await model.loadHistory(query: model.historyQuery) }
            }
            if let detail = model.selectedHistory {
                detailView(detail)
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            if model.history.isEmpty {
                Text("Nothing saved yet.").appType(.caption).foregroundStyle(Tok.text2)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(model.history) { item in
                    HStack(spacing: Space.xs) {
                        AppButton(item.title, glyph: .chevronRight, kind: .quiet, height: 28) {
                            Task { await model.openHistoryItem(item.id) }
                        }
                        Spacer(minLength: 0)
                        AppButton("Copy", glyph: .copy, kind: .quiet, height: 24) {
                            Task { await model.copyHistoryItem(item.id) }
                        }
                        AppButton("Delete", glyph: .delete, kind: .quiet, height: 24) {
                            Task { try? await model.deleteHistoryItem(item.id) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 180)
        .task { await model.loadHistory(query: nil) }
    }

    private func detailView(_ item: IntelligenceHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text(item.title).appType(.label).foregroundStyle(Tok.text)
                Spacer(minLength: 0)
                AppButton("Back", glyph: .chevronLeft, kind: .quiet, height: 24) { model.closeHistory() }
                AppButton("Copy", glyph: .copy, kind: .primary, height: 24) {
                    Task { await model.copyHistoryItem(item.id) }
                }
            }
            ScrollView {
                Text(item.fullText).appType(.reading).foregroundStyle(Tok.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                ForEach(item.answers, id: \.self) { answer in
                    Text(answer).appType(.caption).foregroundStyle(Tok.text2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: 140)
            .padding(Space.sm)
            .background(Tok.well, in: .rect(cornerRadius: Radius.nested, style: .continuous))
        }
    }
}
