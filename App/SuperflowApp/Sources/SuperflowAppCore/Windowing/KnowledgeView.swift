import AppKit
import SuperflowDesignSystem
import SuperflowFeatureDictionary
import SuperflowIcons
import SuperflowFeatureShortcuts
import SuperflowKernel
import SuperflowTextPipeline
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

/// `All` is a reading overview with a preview of each store; a focused scope is
/// the working list. The same `+N more` link moves between them, so overflow is
/// signalled one way everywhere.
private enum KnowledgeSection: Hashable, Sendable {
    case all, dictionary, shortcuts, learned

    static let items: [Segmented<KnowledgeSection>.Item] = [
        .init("All", value: .all), .init("Dictionary", value: .dictionary),
        .init("Shortcuts", value: .shortcuts), .init("Learned", value: .learned),
    ]

    var label: String {
        switch self {
        case .all: "All"
        case .dictionary: "Dictionary"
        case .shortcuts: "Shortcuts"
        case .learned: "Learned"
        }
    }
}

/// Three purposes, top to bottom: what the app knows (one ledger), what you can
/// change (one card per kind, one line per rule), what it is considering (the
/// learning inbox) and a place to try it. Every row is one line with a
/// predictable edge fade; controls live in fixed columns or in the edit dialog.
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

    private let previewLimit = 8

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

    private var lexicon: [LexiconEntry] { dictionary.visibleEntries.filter { $0.source == .user } }
    private var terms: [LexiconEntry] { lexicon.filter { $0.kind == .term } }
    private var corrections: [LexiconEntry] { lexicon.filter { $0.kind == .correction } }
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

    private var pendingCount: Int { learned.filter { $0.state == .suggested }.count }

    /// Search must never hide a match behind the overview preview.
    private func preview<T>(_ items: [T]) -> [T] {
        (section == .all && query.isEmpty) ? Array(items.prefix(previewLimit)) : items
    }

    private var hasVisibleContent: Bool {
        (showDictionary && !lexicon.isEmpty) || (showShortcuts && !phrases.isEmpty)
            || (showLearned && !visibleLearned.isEmpty)
    }

    // MARK: body

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
            ledger
            if let error = dictionary.error ?? shortcuts.error {
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(error).appType(.body).foregroundStyle(Tok.text)
                        AppButton("Retry", kind: .secondary, height: ControlHeight.regular) {
                            Task { await reloadKnowledge() }
                        }
                    }
                }
            } else if dictionary.isLoading || shortcuts.isLoading {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Loading knowledge").appType(.caption).foregroundStyle(Tok.text2)
                }
            }
            if showDictionary {
                groupCard("Terms", note: "Said one way, typed another.",
                          specs: lexiconSpecs(terms), destination: .dictionary)
                groupCard("Corrections", note: "Short fixes you confirmed.",
                          specs: lexiconSpecs(corrections), destination: .dictionary)
            }
            if showShortcuts {
                groupCard("Shortcuts", note: "Triggers expand to your saved text.",
                          specs: shortcutSpecs(phrases), destination: .shortcuts)
            }
            if showLearned { learningGroup }
            if !hasVisibleContent && !dictionary.isLoading && !shortcuts.isLoading && dictionary.error == nil && shortcuts.error == nil {
                EmptyState(query.isEmpty ? "Nothing here yet." : "No matches.",
                           message: query.isEmpty ? "Add a term or a shortcut, or press ⌘N to get started." : "Try another search.")
                    .frame(minHeight: 320)
            }
            if section == .dictionary && query.isEmpty {
                DictionaryPlayground(entries: dictionary.entries)
            }
        }
        .task {
            await reloadKnowledge()
        }
        .onChange(of: query) { _, newValue in
            dictionary.query = newValue
            shortcuts.query = newValue
        }
        .searchShortcut($searchFocus)
        .background { HiddenShortcut("Add Knowledge", key: "n") { add() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let useShortcuts = importingShortcuts
                Task { @MainActor in
                    guard url.startAccessingSecurityScopedResource() else {
                        dictionary.toast.show("Could not access this file.", style: .error)
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    guard let data = try? Data(contentsOf: url) else {
                        dictionary.toast.show("Could not read this file.", style: .error)
                        return
                    }
                    if useShortcuts { _ = await shortcuts.importData(data) }
                    else { _ = await dictionary.importData(data) }
                }
            case .failure(let error):
                dictionary.toast.show("Could not read the file. \(error.localizedDescription)",
                                      style: .error)
            }
        }
    }

    private func reloadKnowledge() async {
        await dictionary.load()
        await shortcuts.load()
        await loadLearned()
    }

    // MARK: sections

    /// Counts are of the whole library, not the current filter, so they never
    /// jitter while the user searches.
    private var ledger: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Knowledge base", note: "Stored locally. Applied as you dictate.")
                HStack(alignment: .top, spacing: Space.lg) {
                    Metric("Terms", value: "\(dictionary.entries.filter { $0.source == .user && $0.kind == .term }.count)", glyph: .dictionary)
                    Metric("Shortcuts", value: "\(shortcuts.entries.count)", glyph: .shortcuts)
                    Metric("Suggestions", value: "\(pendingCount)", glyph: .intelligence)
                }
            }
        }
    }

    private func lexiconSpecs(_ entries: [LexiconEntry]) -> [KnowledgeRowSpec] {
        entries.map { entry in
            KnowledgeRowSpec(id: entry.id,
                             trigger: entry.triggers.first ?? entry.canonical,
                             result: entry.canonical,
                             badge: entry.enabled ? nil : "Off", variant: .neutral,
                             dimmed: !entry.enabled,
                             open: { edit(entry) },
                             delete: { Task { await dictionary.delete(entry) } })
        }
    }

    private func shortcutSpecs(_ entries: [ShortcutEntry]) -> [KnowledgeRowSpec] {
        entries.map { entry in
            let first = (entry.content.components(separatedBy: .newlines).first ?? "")
                .trimmingCharacters(in: .whitespaces)
            return KnowledgeRowSpec(id: entry.id, trigger: entry.trigger, result: first,
                                    badge: entry.match == .inline ? "Inline" : (entry.enabled ? nil : "Off"),
                                    variant: .blue, dimmed: !entry.enabled,
                                    open: { edit(entry) },
                                    delete: { Task { await shortcuts.delete(entry) } })
        }
    }

    private func groupCard(_ title: String, note: String, specs: [KnowledgeRowSpec],
                           destination: KnowledgeSection) -> some View {
        let shown = preview(specs)
        let hidden = specs.count - shown.count
        return VStack(alignment: .leading, spacing: Space.xs) {
            if !shown.isEmpty {
                Card(padding: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title, note: note).padding(.horizontal, Space.sm)
                        ForEach(shown) { KnowledgeRow(spec: $0) }
                        if hidden > 0 {
                            AppButton("+\(hidden) more", kind: .link, height: ControlHeight.small) {
                                section = destination
                            }
                            .accessibilityLabel("Show \(hidden) more in \(destination.label)")
                            .padding(.horizontal, Space.sm).padding(.top, Space.xxs)
                        }
                    }
                }
            }
        }
    }

    private var learningGroup: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionHeader("Learning", note: "Suggestions wait for your confirmation.")
            Card(padding: 8) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    AppToggle("Observe short corrections", isOn: $learningEnabled)
                    AppToggle("Auto-add repeated corrections", isOn: $autoLearnEnabled,
                              enabled: learningEnabled)
                    Text("Local only. Short, editable text fields; never passwords or full documents.")
                        .appType(.caption).foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !visibleLearned.isEmpty {
                        ForEach(visibleLearned) { candidate in
                            LearningRow(candidate: candidate,
                                        onConfirm: { Task { await confirm(candidate) } },
                                        onReject: { Task { await reject(candidate) } },
                                        onUndo: { Task { await undo(candidate) } })
                        }
                    }
                }
                .padding(.horizontal, Space.sm)
            }
        }
    }

    // MARK: learning actions

    private func loadLearned() async {
        do { learned = try await learning.candidates() }
        catch { dictionary.toast.show("Could not load learned corrections.", style: .error) }
    }

    private func confirm(_ candidate: LearningCandidate) async {
        do {
            try await learning.confirm(id: candidate.id)
            await dictionary.load(); await loadLearned(); await onLearningChange()
            dictionary.toast.show("Added to Knowledge.", style: .success)
        } catch { dictionary.toast.show("Could not confirm correction.", style: .error) }
    }

    private func reject(_ candidate: LearningCandidate) async {
        do { try await learning.reject(id: candidate.id); await loadLearned() }
        catch { dictionary.toast.show("Could not reject correction.", style: .error) }
    }

    private func undo(_ candidate: LearningCandidate) async {
        do {
            try await learning.undo(id: candidate.id)
            await dictionary.load(); await loadLearned(); await onLearningChange()
            dictionary.toast.show("Learned correction removed.", style: .success)
        } catch { dictionary.toast.show("Could not undo correction.", style: .error) }
    }

    // MARK: add / edit / files

    private func add() { section == .shortcuts ? addShortcut() : addTerm() }

    private func addTerm() {
        dialogs.present { TermDialog { draft in Task { _ = await dictionary.save(draft) } } }
    }

    private func addShortcut() {
        dialogs.present { ShortcutDialog { draft in Task { _ = await shortcuts.save(draft) } } }
    }

    private func edit(_ entry: LexiconEntry) {
        dialogs.present {
            TermDialog(existing: entry) { draft in Task { _ = await dictionary.save(draft) } }
        }
    }

    private func edit(_ entry: ShortcutEntry) {
        dialogs.present {
            ShortcutDialog(existing: entry) { draft in Task { _ = await shortcuts.save(draft) } }
        }
    }

    private func exportTerms() { save(dictionary.exportData(), name: "superflow-dictionary.json") }
    private func exportShortcuts() { save(shortcuts.exportData(), name: "superflow-shortcuts.json") }

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
