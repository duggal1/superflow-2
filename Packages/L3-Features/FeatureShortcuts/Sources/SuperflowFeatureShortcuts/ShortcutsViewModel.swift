import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextLexicon
import SuperflowTextShortcuts
import SuperflowUIComponents
import SwiftUI

public enum ShortcutFilter: String, CaseIterable, Sendable {
    case all, wholeUtterance, inline

    public var label: String {
        switch self {
        case .all: "All"
        case .wholeUtterance: "Whole utterance"
        case .inline: "Inline"
        }
    }

    public var match: ShortcutMatch? {
        switch self {
        case .all: nil
        case .wholeUtterance: .wholeUtterance
        case .inline: .inline
        }
    }
}

@MainActor
public final class ShortcutsViewModel: ObservableObject {
    @Published public private(set) var entries: [ShortcutEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    @Published public var query = ""
    @Published public var filter: ShortcutFilter = .all

    public let toast: ToastCenter
    private let repository: any LibraryRepository
    private let onChange: (@MainActor () -> Void)?
    private var deleted: ShortcutEntry?

    public init(repository: any LibraryRepository, toast: ToastCenter = ToastCenter(),
                onChange: (@MainActor () -> Void)? = nil) {
        self.repository = repository
        self.toast = toast
        self.onChange = onChange
    }

    public var visibleEntries: [ShortcutEntry] {
        entries
            .filter { filter.match == nil || $0.match == filter.match }
            .filter { matches($0, query: query) }
            .sorted { lhs, rhs in
                if lhs.enabled != rhs.enabled { return lhs.enabled }
                return lhs.trigger.localizedCaseInsensitiveCompare(rhs.trigger) == .orderedAscending
            }
    }

    public var isEmpty: Bool { !isLoading && visibleEntries.isEmpty }

    public func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            entries = try await repository.shortcuts()
        } catch {
            self.error = "Could not load shortcuts. \(error.localizedDescription)"
        }
    }

    public func draft(for entry: ShortcutEntry) -> ShortcutDraft {
        ShortcutDraft(entry: entry)
    }

    public func issues(for draft: ShortcutDraft) -> [ShortcutIssue] {
        ShortcutValidation.issues(draft: draft, existing: entries)
    }

    @discardableResult
    public func save(_ draft: ShortcutDraft) async -> Bool {
        guard ShortcutValidation.isValid(draft, existing: entries) else {
            toast.show("Fix the highlighted fields first.", style: .warning)
            return false
        }
        do {
            let entry = draft.entry
            try await repository.saveShortcut(entry)
            entries.removeAll { $0.id == entry.id }
            entries.append(entry)
            onChange?()
            toast.show("Saved “\(entry.trigger)”.")
            return true
        } catch {
            toast.show("Could not save this shortcut. \(error.localizedDescription)", style: .error)
            return false
        }
    }

    public func toggle(_ entry: ShortcutEntry) async {
        var updated = entry
        updated.enabled.toggle()
        do {
            try await repository.saveShortcut(updated)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = updated
            }
            onChange?()
        } catch {
            toast.show("Could not update this shortcut. \(error.localizedDescription)", style: .error)
        }
    }

    public func delete(_ entry: ShortcutEntry) async {
        do {
            deleted = entry
            try await repository.deleteShortcut(id: entry.id)
            entries.removeAll { $0.id == entry.id }
            onChange?()
            toast.show("Deleted “\(entry.trigger)”.", actionTitle: "Undo") { [weak self] in
                Task { await self?.undoDelete() }
            }
        } catch {
            toast.show("Could not delete this shortcut. \(error.localizedDescription)", style: .error)
        }
    }

    public func undoDelete() async {
        guard let deleted else { return }
        do {
            try await repository.saveShortcut(deleted)
            entries.append(deleted)
            self.deleted = nil
            onChange?()
            toast.show("Restored “\(deleted.trigger)”.", style: .success)
        } catch {
            toast.show("Could not restore this shortcut. \(error.localizedDescription)", style: .error)
        }
    }

    /// Runs the real expansion stage so the editor previews exactly what will
    /// be inserted. Saved entries respect their enabled flag; candidates passed
    /// explicitly (for example the shortcut being edited) are forced on.
    public func preview(_ utterance: String, using candidates: [ShortcutEntry]? = nil) async -> String {
        let list: [ShortcutEntry]
        if let candidates {
            list = candidates.map { entry -> ShortcutEntry in
                var copy = entry
                copy.enabled = true
                return copy
            }
        } else {
            list = entries
        }
        let stage = ShortcutsStage(entries: list)
        let result = await stage.apply(TranscriptDraft(text: utterance), context: TextContext())
        return result.text
    }

    public func exportData() -> Data? {
        do {
            return try ShortcutDocument(entries: entries).encoded()
        } catch {
            toast.show("Could not build the export. \(error.localizedDescription)", style: .error)
            return nil
        }
    }

    public func importData(_ data: Data) async -> ShortcutImportResult {
        do {
            let document = try ShortcutDocument.decode(data)
            guard !document.entries.isEmpty else {
                toast.show(ShortcutDocumentError.noEntries.localizedDescription, style: .warning)
                return ShortcutImportResult()
            }
            var result = ShortcutImportResult()
            var known = Set(entries.map { ShortcutValidation.normalized($0.trigger) })
            var knownIDs = Set(entries.map(\.id))
            for raw in document.entries {
                let draft = ShortcutDraft(entry: raw)
                let key = ShortcutValidation.normalized(draft.trigger)
                guard !draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      draft.contentBytes <= ShortcutsStage.maxContentBytes,
                      !key.isEmpty, !known.contains(key) else {
                    result.skipped += 1
                    continue
                }
                var entry = draft.entry
                if entry.id.isEmpty || knownIDs.contains(entry.id) {
                    entry.id = UUID().uuidString
                }
                do {
                    try await repository.saveShortcut(entry)
                    entries.append(entry)
                    known.insert(key)
                    knownIDs.insert(entry.id)
                    result.imported += 1
                    if CommonWords.isRisky(trigger: draft.trigger) {
                        result.warnings.append("“\(draft.trigger)” uses common words.")
                    }
                } catch {
                    result.skipped += 1
                }
            }
            await load()
            onChange?()
            toast.show(result.summary, style: result.imported > 0 ? .success : .warning)
            return result
        } catch {
            toast.show("Could not import this file. \(error.localizedDescription)", style: .error)
            return ShortcutImportResult()
        }
    }

    private func matches(_ entry: ShortcutEntry, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return entry.trigger.localizedCaseInsensitiveContains(needle)
            || entry.content.localizedCaseInsensitiveContains(needle)
    }
}
