import AppKit
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

public struct DictionaryView: View {
    @ObservedObject private var model: DictionaryViewModel
    @Environment(DialogHost.self) private var dialogs
    @State private var scope: EntryScope = .personal
    @State private var bundledExpanded = false
    @State private var importing = false
    @State private var searchFocus = false

    public init(model: DictionaryViewModel) {
        self.model = model
    }

    public var body: some View {
        Page(title: "Dictionary") {
            ListControls(scope: $scope, scopes: EntryScope.items,
                         query: $model.query, prompt: "Search terms",
                         searchFocus: $searchFocus, addTitle: "Add term",
                         menu: [
                            .init("Import…") { importing = true },
                            .init("Export…") { export() },
                         ],
                         onAdd: add)
            if scope == .shared {
                EmptyState("Nothing shared yet.",
                           message: "Shared terms appear here.",
                           density: .pane)
                    .frame(minHeight: 320)
            } else if model.isEmpty {
                EmptyState("Nothing here yet.",
                           message: "Press ⌘N to add a term, or try a phrase in the playground.")
                    .frame(minHeight: 320)
            } else {
                groups
            }
            if scope == .personal {
                DictionaryPlayground(entries: model.entries)
            }
        }
        .task { await model.load() }
        .searchShortcut($searchFocus)
        .background {
            HiddenShortcut("Add term", key: "n") { add() }
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

    // MARK: groups

    private var userEntries: [LexiconEntry] {
        model.visibleEntries.filter { $0.source == .user }
    }

    private var terms: [LexiconEntry] { userEntries.filter { $0.kind == .term } }
    private var corrections: [LexiconEntry] { userEntries.filter { $0.kind == .correction } }
    private var bundled: [LexiconEntry] { model.visibleEntries.filter { $0.source == .bundled } }

    @ViewBuilder
    private var groups: some View {
        if !terms.isEmpty {
            group("Terms", entries: terms)
        }
        if !corrections.isEmpty {
            group("Corrections", entries: corrections)
        }
        if !bundled.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                AppButton(bundledExpanded ? "Hide bundled terms" : "Show \(bundled.count) bundled terms",
                          kind: .quiet) {
                    bundledExpanded.toggle()
                }
                if bundledExpanded {
                    entryList(bundled)
                }
            }
        }
    }

    private func group(_ title: String, entries: [LexiconEntry]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .appType(.caption)
                .foregroundStyle(Tok.text2)
            entryList(entries)
        }
    }

    private func entryList(_ entries: [LexiconEntry]) -> some View {
        LazyVGrid(columns: [.init(.flexible(), spacing: 16), .init(.flexible())],
                  alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                EntryRow(trigger: entry.triggers.first ?? entry.canonical,
                         result: entry.canonical,
                         isDisabled: !entry.enabled,
                         onOpen: { edit(entry) },
                         onDelete: { Task { await model.delete(entry) } })
            }
        }
    }

    private func add() {
        dialogs.present {
            TermDialog { draft in
                Task { _ = await model.save(draft) }
            }
        }
    }

    private func edit(_ entry: LexiconEntry) {
        dialogs.present {
            TermDialog(existing: entry) { draft in
                Task { _ = await model.save(draft) }
            }
        }
    }

    private func export() {
        guard let data = model.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "superflow-dictionary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            model.toast.show("Dictionary exported.", style: .success)
        } catch {
            model.toast.show("Could not write the file. \(error.localizedDescription)", style: .error)
        }
    }
}
