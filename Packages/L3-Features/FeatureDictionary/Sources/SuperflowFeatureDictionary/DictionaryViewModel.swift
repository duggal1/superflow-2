import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI

public enum LexiconFilter: String, CaseIterable, Sendable {
    case all, terms, corrections

    public var label: String {
        switch self {
        case .all: "All"
        case .terms: "Terms"
        case .corrections: "Corrections"
        }
    }

    public var kind: LexiconKind? {
        switch self {
        case .all: nil
        case .terms: .term
        case .corrections: .correction
        }
    }
}

@MainActor
public final class DictionaryViewModel: ObservableObject {
    @Published public private(set) var entries: [LexiconEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    @Published public var query = ""
    @Published public var filter: LexiconFilter = .all

    public let toast: ToastCenter
    private let repository: any LibraryRepository
    private let onChange: (@MainActor () -> Void)?
    private var deleted: LexiconEntry?

    public init(repository: any LibraryRepository, toast: ToastCenter = ToastCenter(),
                onChange: (@MainActor () -> Void)? = nil) {
        self.repository = repository
        self.toast = toast
        self.onChange = onChange
    }

    public var visibleEntries: [LexiconEntry] {
        entries
            .filter { filter.kind == nil || $0.kind == filter.kind }
            .filter { matches($0, query: query) }
            .sorted { lhs, rhs in
                if lhs.enabled != rhs.enabled { return lhs.enabled }
                return lhs.canonical.localizedCaseInsensitiveCompare(rhs.canonical) == .orderedAscending
            }
    }

    public var userEntryCount: Int { entries.filter { $0.source == .user }.count }
    public var isEmpty: Bool { !isLoading && visibleEntries.isEmpty }

    public func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            entries = try await repository.lexicon()
        } catch {
            self.error = "Could not load the dictionary. \(error.localizedDescription)"
        }
    }

    public func draft(for entry: LexiconEntry) -> LexiconDraft {
        LexiconDraft(entry: entry)
    }

    public func issues(for draft: LexiconDraft) -> [LexiconIssue] {
        LexiconValidation.issues(draft: draft, existing: entries)
    }

    @discardableResult
    public func save(_ draft: LexiconDraft) async -> Bool {
        guard LexiconValidation.isValid(draft, existing: entries) else {
            toast.show("Fix the highlighted fields first.", style: .warning)
            return false
        }
        do {
            let entry = draft.entry
            try await repository.saveLexicon(entry)
            entries.removeAll { $0.id == entry.id }
            entries.append(entry)
            onChange?()
            toast.show("Saved “\(entry.canonical)”.")
            return true
        } catch {
            toast.show("Could not save this entry. \(error.localizedDescription)", style: .error)
            return false
        }
    }

    public func toggle(_ entry: LexiconEntry) async {
        var updated = entry
        updated.enabled.toggle()
        do {
            try await repository.saveLexicon(updated)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = updated
            }
            onChange?()
        } catch {
            toast.show("Could not update this entry. \(error.localizedDescription)", style: .error)
        }
    }

    public func delete(_ entry: LexiconEntry) async {
        guard entry.source == .user else {
            toast.show("Bundled terms can be turned off, not deleted.", style: .warning)
            return
        }
        do {
            deleted = entry
            try await repository.deleteLexicon(id: entry.id)
            entries.removeAll { $0.id == entry.id }
            onChange?()
            toast.show("Deleted “\(entry.canonical)”.", actionTitle: "Undo") { [weak self] in
                Task { await self?.undoDelete() }
            }
        } catch {
            toast.show("Could not delete this entry. \(error.localizedDescription)", style: .error)
        }
    }

    public func undoDelete() async {
        guard let deleted else { return }
        do {
            try await repository.saveLexicon(deleted)
            entries.append(deleted)
            self.deleted = nil
            onChange?()
            toast.show("Restored “\(deleted.canonical)”.", style: .success)
        } catch {
            toast.show("Could not restore this entry. \(error.localizedDescription)", style: .error)
        }
    }

    public func exportData() -> Data? {
        let userEntries = entries.filter { $0.source == .user }
        do {
            return try LexiconDocument(entries: userEntries).encoded()
        } catch {
            toast.show("Could not build the export. \(error.localizedDescription)", style: .error)
            return nil
        }
    }

    public func importData(_ data: Data) async -> LexiconImportResult {
        do {
            let document = try LexiconDocument.decode(data)
            guard !document.entries.isEmpty else {
                toast.show(LexiconDocumentError.noEntries.localizedDescription, style: .warning)
                return LexiconImportResult()
            }
            var result = LexiconImportResult()
            var known = Set(entries.flatMap { $0.triggers.map(LexiconValidation.normalized) })
            var knownIDs = Set(entries.map(\.id))
            for raw in document.entries {
                let draft = LexiconDraft(entry: raw).cleaned
                let keys = draft.triggers.map(LexiconValidation.normalized)
                guard !draft.triggers.isEmpty, !draft.canonical.isEmpty,
                      draft.canonical.count <= LexiconValidation.maxCanonicalLength,
                      keys.allSatisfy({ !$0.isEmpty && !known.contains($0) }) else {
                    result.skipped += 1
                    continue
                }
                var entry = draft.entry
                entry.source = .user
                if entry.id.isEmpty || knownIDs.contains(entry.id) {
                    entry.id = UUID().uuidString
                }
                do {
                    try await repository.saveLexicon(entry)
                    entries.append(entry)
                    keys.forEach { known.insert($0) }
                    knownIDs.insert(entry.id)
                    result.imported += 1
                    let risky = draft.triggers.filter { CommonWords.isRisky(trigger: $0) }
                    if !risky.isEmpty {
                        result.warnings.append("“\(risky.joined(separator: ", "))” uses common words.")
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
            return LexiconImportResult()
        }
    }

    private func matches(_ entry: LexiconEntry, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if entry.canonical.localizedCaseInsensitiveContains(needle) { return true }
        return entry.triggers.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}
