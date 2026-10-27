import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowTextShortcuts
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

public struct ShortcutsView: View {
    @ObservedObject private var model: ShortcutsViewModel
    @State private var trigger = ""
    @State private var content = ""
    @State private var expandedID: String?
    @State private var importing = false
    @State private var searchFocus = false
    @FocusState private var triggerFocused: Bool

    public init(model: ShortcutsViewModel) {
        self.model = model
    }

    public var body: some View {
        Page(title: "Shortcuts") {
            SearchField(text: $model.query, prompt: "Search shortcuts", isFocused: $searchFocus)
        } trailing: {
            ActionMenu(actions: [
                .init("Import…") { importing = true },
                .init("Export…") { export() },
            ])
            AppButton("Add shortcut", glyph: .add, kind: .primary, height: Layout.control) {
                triggerFocused = true
            }
        } content: {
            composer
            if model.isEmpty {
                EmptyState("Nothing here yet.",
                           message: "Add a phrase above. Say it while dictating and the text lands in full.")
            } else {
                list
            }
        }
        .task { await model.load() }
        .searchShortcut($searchFocus)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    guard let data = try? Data(contentsOf: url) else { return }
                    _ = await model.importData(data)
                }
            case .failure(let error):
                model.toast.show("Could not read that file. \(error.localizedDescription)",
                                 style: .error)
            }
        }
    }

    private var composer: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Text("Say")
                        .font(Typography.body)
                        .foregroundStyle(Tok.text2)
                    AppField("Trigger", prompt: "sign off", text: $trigger,
                             onSubmit: add)
                        .frame(maxWidth: 260)
                        .focused($triggerFocused)
                    Spacer(minLength: Space.md)
                }
                AppTextEditor("Shortcut text", text: $content, minHeight: 96)
                if let counter = byteCounter {
                    Text(counter)
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                }
            }
        }
    }

    private var canAdd: Bool {
        !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The limit is stated only when it is close: never as a permanent footnote.
    private var byteCounter: String? {
        let limit = ShortcutsStage.maxContentBytes
        let bytes = content.utf8.count
        guard bytes > Int(Double(limit) * 0.8) else { return nil }
        return "\(bytes / 1024) KB of \(limit / 1024) KB"
    }

    private func add() {
        guard canAdd else { return }
        let draft = ShortcutDraft(trigger: trigger, content: content)
        Task {
            if await model.save(draft) {
                trigger = ""
                content = ""
                triggerFocused = true
            }
        }
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(model.visibleEntries) { entry in
                VStack(spacing: 2) {
                    EntryRow(trigger: entry.trigger,
                             result: firstLine(entry.content),
                             badge: entry.match == .inline ? "Inline" : nil,
                             badgeVariant: .blue,
                             isDisabled: !entry.enabled,
                             onOpen: { expandedID = expandedID == entry.id ? nil : entry.id },
                             onDelete: { Task { await model.delete(entry) } })
                    if expandedID == entry.id {
                        ShortcutRowEditor(model: model, entry: entry) { expandedID = nil }
                    }
                }
            }
        }
    }

    private func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return line.isEmpty ? text : line
    }

    private func export() {
        guard let data = model.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "superflow-shortcuts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            model.toast.show("Shortcuts exported.", style: .success)
        } catch {
            model.toast.show("Could not write the file. \(error.localizedDescription)", style: .error)
        }
    }
}
