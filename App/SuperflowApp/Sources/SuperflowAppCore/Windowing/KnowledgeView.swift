import AppKit
import SuperflowDesignSystem
import SuperflowFeatureDictionary
import SuperflowFeatureShortcuts
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

private enum KnowledgeSection: Hashable {
    case all, dictionary, shortcuts

    static let items: [Segmented<KnowledgeSection>.Item] = [
        .init("All", value: .all),
        .init("Dictionary", value: .dictionary),
        .init("Shortcuts", value: .shortcuts),
    ]
}

/// One page for the two existing capabilities, with the same SQLite-backed
/// models and import/export contracts. Neither table nor expansion logic moves.
struct KnowledgeView: View {
    @ObservedObject var dictionary: DictionaryViewModel
    @ObservedObject var shortcuts: ShortcutsViewModel
    @Environment(DialogHost.self) private var dialogs
    @State private var section: KnowledgeSection = .all
    @State private var query = ""
    @State private var searchFocus = false
    @State private var importing = false
    @State private var importingShortcuts = false

    private var lexicon: [LexiconEntry] {
        dictionary.visibleEntries.filter { $0.source == .user }
    }
    private var phrases: [ShortcutEntry] { shortcuts.visibleEntries }
    private var showDictionary: Bool { section != .shortcuts }
    private var showShortcuts: Bool { section != .dictionary }

    var body: some View {
        Page(title: "Knowledge") {
            ListControls(scope: $section, scopes: KnowledgeSection.items,
                         query: $query, prompt: "Search terms and shortcuts",
                         searchFocus: $searchFocus, addTitle: "Add",
                         menu: [
                            .init("Add shortcut") { addShortcut() },
                            .init("Import terms…") { importingShortcuts = false; importing = true },
                            .init("Import shortcuts…") { importingShortcuts = true; importing = true },
                            .init("Export terms…") { exportTerms() },
                            .init("Export shortcuts…") { exportShortcuts() },
                         ], onAdd: add)
            if showDictionary {
                if !lexicon.filter({ $0.kind == .term }).isEmpty {
                    dictionaryGroup("Terms", entries: lexicon.filter { $0.kind == .term })
                }
                if !lexicon.filter({ $0.kind == .correction }).isEmpty {
                    dictionaryGroup("Corrections", entries: lexicon.filter { $0.kind == .correction })
                }
            }
            if showShortcuts, !phrases.isEmpty {
                shortcutsGroup
            }
            if (!showDictionary || lexicon.isEmpty)
                && (!showShortcuts || phrases.isEmpty)
                && !dictionary.isLoading && !shortcuts.isLoading {
                EmptyState("Nothing here yet.",
                           message: "Add a term or a shortcut to get started.")
                    .frame(minHeight: 320)
            }
            if showDictionary { DictionaryPlayground(entries: dictionary.entries) }
        }
        .task {
            await dictionary.load()
            await shortcuts.load()
        }
        .onChange(of: query) { _, newValue in
            dictionary.query = newValue
            shortcuts.query = newValue
        }
        .searchShortcut($searchFocus)
        .background {
            HiddenShortcut("Add Knowledge", key: "n") { add() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let useShortcuts = importingShortcuts
                Task { @MainActor in
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    guard let data = try? Data(contentsOf: url) else { return }
                    if useShortcuts { _ = await shortcuts.importData(data) }
                    else { _ = await dictionary.importData(data) }
                }
            case .failure(let error):
                dictionary.toast.show("Could not read the file. \(error.localizedDescription)",
                                      style: .error)
            }
        }
    }

    private func dictionaryGroup(_ title: String, entries: [LexiconEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title, note: "\(entries.count) entries")
            Card(padding: 8) {
                VStack(spacing: 2) {
                    ForEach(entries) { entry in
                        EntryRow(trigger: entry.triggers.first ?? entry.canonical,
                                 result: entry.canonical,
                                 isDisabled: !entry.enabled,
                                 onOpen: { edit(entry) },
                                 onDelete: { Task { await dictionary.delete(entry) } })
                    }
                }
            }
        }
    }

    private var shortcutsGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Shortcuts", note: "\(phrases.count) saved phrases")
            Card(padding: 8) {
                VStack(spacing: 2) {
                    ForEach(phrases) { entry in
                        EntryRow(trigger: entry.trigger,
                                 result: entry.content.components(separatedBy: .newlines).first ?? "",
                                 badge: entry.match == .inline ? "Inline" : nil,
                                 badgeVariant: .blue,
                                 isDisabled: !entry.enabled,
                                 onOpen: { edit(entry) },
                                 onDelete: { Task { await shortcuts.delete(entry) } })
                    }
                }
            }
        }
    }

    private func add() {
        if section == .shortcuts { addShortcut() }
        else { addTerm() }
    }

    private func addTerm() {
        dialogs.present {
            TermDialog { draft in Task { _ = await dictionary.save(draft) } }
        }
    }

    private func addShortcut() {
        dialogs.present {
            ShortcutDialog { draft in Task { _ = await shortcuts.save(draft) } }
        }
    }

    private func edit(_ entry: LexiconEntry) {
        dialogs.present {
            TermDialog(existing: entry) { draft in
                Task { _ = await dictionary.save(draft) }
            }
        }
    }

    private func edit(_ entry: ShortcutEntry) {
        dialogs.present {
            ShortcutDialog(existing: entry) { draft in
                Task { _ = await shortcuts.save(draft) }
            }
        }
    }

    private func exportTerms() {
        save(dictionary.exportData(), name: "superflow-dictionary.json")
    }

    private func exportShortcuts() {
        save(shortcuts.exportData(), name: "superflow-shortcuts.json")
    }

    private func save(_ data: Data?, name: String) {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            dictionary.toast.show("Exported \(name).", style: .success)
        } catch {
            dictionary.toast.show("Could not export. \(error.localizedDescription)", style: .error)
        }
    }
}
