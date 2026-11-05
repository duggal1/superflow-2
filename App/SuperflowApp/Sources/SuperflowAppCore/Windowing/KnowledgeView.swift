import AppKit
import SuperflowDesignSystem
import SuperflowFeatureDictionary
import SuperflowFeatureShortcuts
import SuperflowKernel
import SuperflowTextPipeline
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

private enum KnowledgeSection: Hashable, Sendable {
    case all, dictionary, shortcuts, learned

    static let items: [Segmented<KnowledgeSection>.Item] = [
        .init("All", value: .all),
        .init("Dictionary", value: .dictionary),
        .init("Shortcuts", value: .shortcuts),
        .init("Learned", value: .learned),
    ]
}

/// One page for the two existing capabilities, with the same SQLite-backed
/// models and import/export contracts. Neither table nor expansion logic moves.
struct KnowledgeView: View {
    @ObservedObject var dictionary: DictionaryViewModel
    @ObservedObject var shortcuts: ShortcutsViewModel
    let learning: DictionaryLearningEngine
    @Binding var learningEnabled: Bool
    @Binding var autoLearnEnabled: Bool
    let onLearningChange: @MainActor () async -> Void
    @Environment(DialogHost.self) private var dialogs
    @State private var section: KnowledgeSection = .all
    @State private var query = ""
    @State private var searchFocus = false
    @State private var importing = false
    @State private var importingShortcuts = false
    @State private var learned: [LearningCandidate] = []

    init(dictionary: DictionaryViewModel, shortcuts: ShortcutsViewModel,
         learning: DictionaryLearningEngine, learningEnabled: Binding<Bool>,
         autoLearnEnabled: Binding<Bool>,
         onLearningChange: @escaping @MainActor () async -> Void) {
        self.dictionary = dictionary
        self.shortcuts = shortcuts
        self.learning = learning
        _learningEnabled = learningEnabled
        _autoLearnEnabled = autoLearnEnabled
        self.onLearningChange = onLearningChange
    }

    private var lexicon: [LexiconEntry] {
        dictionary.visibleEntries.filter { $0.source == .user }
    }
    private var phrases: [ShortcutEntry] { shortcuts.visibleEntries }
    private var showDictionary: Bool { section == .all || section == .dictionary }
    private var showShortcuts: Bool { section == .all || section == .shortcuts }
    private var showLearned: Bool { section == .all || section == .learned }
    private var visibleLearned: [LearningCandidate] {
        learned.filter { $0.state != .rejected }
            .filter {
                query.isEmpty || $0.heard.localizedCaseInsensitiveContains(query)
                    || $0.canonical.localizedCaseInsensitiveContains(query)
            }
    }

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
            if showLearned { learningGroup }
            if (!showDictionary || lexicon.isEmpty)
                && (!showShortcuts || phrases.isEmpty)
                && (!showLearned || visibleLearned.isEmpty)
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
            await loadLearned()
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

    private var learningGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Learning", note: "Suggestions require confirmation.")
            HStack(spacing: 16) {
                AppToggle("Observe short corrections", isOn: $learningEnabled)
                AppToggle("Auto-add repeated corrections", isOn: $autoLearnEnabled,
                          enabled: learningEnabled)
            }
            Text("Local only. Short, editable text fields; never passwords or full documents.")
                .appType(.caption).foregroundStyle(Tok.text2)
            if !visibleLearned.isEmpty {
                Card(padding: 8) {
                    VStack(spacing: 2) {
                        ForEach(visibleLearned) { candidate in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.heard + " → " + candidate.canonical)
                                        .appType(.body).foregroundStyle(Tok.text)
                                    Text(candidate.appScope ?? "All apps")
                                        .appType(.caption).foregroundStyle(Tok.text2)
                                }
                                Spacer(minLength: 12)
                                if candidate.state == .suggested {
                                    AppButton("Confirm", kind: .quiet, height: 28) {
                                        Task { await confirm(candidate) }
                                    }
                                    AppButton("Reject", kind: .quiet, height: 28) {
                                        Task { await reject(candidate) }
                                    }
                                } else {
                                    AppButton("Undo", kind: .quiet, height: 28) {
                                        Task { await undo(candidate) }
                                    }
                                }
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
            }
        }
    }

    private func loadLearned() async {
        do { learned = try await learning.candidates() }
        catch { dictionary.toast.show("Could not load learned corrections.", style: .error) }
    }

    private func confirm(_ candidate: LearningCandidate) async {
        do {
            try await learning.confirm(id: candidate.id)
            await dictionary.load()
            await loadLearned()
            await onLearningChange()
            dictionary.toast.show("Added to Knowledge.", style: .success)
        } catch {
            dictionary.toast.show("Could not confirm correction.", style: .error)
        }
    }

    private func reject(_ candidate: LearningCandidate) async {
        do {
            try await learning.reject(id: candidate.id)
            await loadLearned()
        } catch {
            dictionary.toast.show("Could not reject correction.", style: .error)
        }
    }

    private func undo(_ candidate: LearningCandidate) async {
        do {
            try await learning.undo(id: candidate.id)
            await dictionary.load()
            await loadLearned()
            await onLearningChange()
            dictionary.toast.show("Learned correction removed.", style: .success)
        } catch {
            dictionary.toast.show("Could not undo correction.", style: .error)
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
