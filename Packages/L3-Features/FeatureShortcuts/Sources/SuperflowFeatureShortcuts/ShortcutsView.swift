import AppKit
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

public struct ShortcutsView: View {
    @ObservedObject private var model: ShortcutsViewModel
    @Environment(DialogHost.self) private var dialogs
    @State private var scope: EntryScope = .personal
    @State private var importing = false
    @State private var searchFocus = false

    public init(model: ShortcutsViewModel) {
        self.model = model
    }

    public var body: some View {
        Page(title: "Shortcuts") {
            ListControls(scope: $scope, scopes: EntryScope.items,
                         query: $model.query, prompt: "Search shortcuts",
                         searchFocus: $searchFocus, addTitle: "Add shortcut",
                         menu: [
                            .init("Import…") { importing = true },
                            .init("Export…") { export() },
                         ],
                         onAdd: add)
            if scope == .shared {
                EmptyState("Nothing shared yet.",
                           message: "Shared shortcuts appear here.",
                           density: .pane)
                    .frame(minHeight: 320)
            } else if model.isEmpty {
                EmptyState("Nothing here yet.",
                           message: "Press ⌘N to add a phrase.")
                    .frame(minHeight: 320)
            } else {
                list
            }
        }
        .task { await model.load() }
        .searchShortcut($searchFocus)
        .background {
            HiddenShortcut("Add shortcut", key: "n") { add() }
        }
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

    private var list: some View {
        LazyVGrid(columns: [.init(.flexible(), spacing: 16), .init(.flexible())],
                  alignment: .leading, spacing: 4) {
            ForEach(model.visibleEntries) { entry in
                EntryRow(trigger: entry.trigger,
                         result: firstLine(entry.content),
                         badge: entry.match == .inline ? "Inline" : nil,
                         badgeVariant: .blue,
                         isDisabled: !entry.enabled,
                         onOpen: { edit(entry) },
                         onDelete: { Task { await model.delete(entry) } })
            }
        }
    }

    private func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        return line.isEmpty ? text : line
    }

    private func add() {
        dialogs.present {
            ShortcutDialog { draft in
                Task { _ = await model.save(draft) }
            }
        }
    }

    private func edit(_ entry: ShortcutEntry) {
        dialogs.present {
            ShortcutDialog(existing: entry) { draft in
                Task { _ = await model.save(draft) }
            }
        }
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
