import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

public struct DictionaryView: View {
    @ObservedObject private var model: DictionaryViewModel
    @State private var say = ""
    @State private var get = ""
    @State private var expandedID: String?
    @State private var bundledExpanded = false
    @State private var importing = false
    @State private var searchFocus = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case say, get
    }

    public init(model: DictionaryViewModel) {
        self.model = model
    }

    public var body: some View {
        Page(title: "Dictionary") {
            SearchField(text: $model.query, prompt: "Search terms", isFocused: $searchFocus)
        } trailing: {
            ActionMenu(actions: [
                .init("Import…") { importing = true },
                .init("Export…") { export() },
            ])
            AppButton("Add term", glyph: .add, kind: .primary, height: Layout.control) {
                focus = .say
            }
        } content: {
            composer
            if model.isEmpty {
                EmptyState("Nothing here yet.",
                           message: "Add a term in the row above, or try a phrase in the playground.")
            } else {
                groups
            }
            DictionaryPlayground(entries: model.entries)
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

    // MARK: composer

    private var composer: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text("You say")
                        .font(Typography.body)
                        .foregroundStyle(Tok.text2)
                    AppField("Trigger", prompt: "next js", text: $say,
                             onSubmit: add, onTab: { focus = .get })
                        .frame(maxWidth: 220)
                        .focused($focus, equals: .say)
                    Icon(.arrow, size: 12, tint: Tok.text2)
                    Text("You get")
                        .font(Typography.body)
                        .foregroundStyle(Tok.text2)
                    AppField("Replacement", prompt: "Next.js", text: $get,
                             onSubmit: add)
                        .frame(maxWidth: 220)
                        .focused($focus, equals: .get)
                    Spacer(minLength: 0)
                    if commonPhrase { Badge("Common phrase", variant: .orange) }
                }
                if commonPhrase {
                    Text("“\(say)” is made only of common words, so it may rewrite ordinary speech.")
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                }
            }
        }
    }

    private var canAdd: Bool {
        !say.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !get.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var commonPhrase: Bool {
        let trimmed = say.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && CommonWords.isRisky(trigger: trimmed)
    }

    private func add() {
        guard canAdd else { return }
        var draft = LexiconDraft(kind: .term, triggers: [say], canonical: get)
        draft.id = nil
        Task {
            if await model.save(draft) {
                say = ""
                get = ""
                focus = .say
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
                          kind: .quiet, action: { bundledExpanded.toggle() })
                if bundledExpanded {
                    entryList(bundled)
                }
            }
        }
    }

    private func group(_ title: String, entries: [LexiconEntry]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionHeader(title)
            entryList(entries)
        }
    }

    private func entryList(_ entries: [LexiconEntry]) -> some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                VStack(spacing: 2) {
                    EntryRow(trigger: entry.triggers.first ?? entry.canonical,
                             result: entry.canonical,
                             isDisabled: !entry.enabled,
                             onOpen: { expandedID = expandedID == entry.id ? nil : entry.id },
                             onDelete: { Task { await model.delete(entry) } })
                    if expandedID == entry.id {
                        LexiconRowEditor(model: model, entry: entry) { expandedID = nil }
                    }
                }
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
