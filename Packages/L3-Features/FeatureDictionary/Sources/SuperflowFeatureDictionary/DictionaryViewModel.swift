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
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return search(query).filter { filter.kind == nil || $0.kind == filter.kind }
        }
        return entries
            .filter { filter.kind == nil || $0.kind == filter.kind }
            .sorted { lhs, rhs in
                if lhs.enabled != rhs.enabled { return lhs.enabled }
                let name = lhs.canonical.localizedCaseInsensitiveCompare(rhs.canonical)
                if name != .orderedSame { return name == .orderedAscending }
                return lhs.id < rhs.id
            }
    }

    /// Tokenised, multi-term (AND), case/diacritic-insensitive full-text search
    /// with a stable ranking. An empty query returns every entry.
    public func search(_ query: String) -> [LexiconEntry] {
        let scored: [(entry: LexiconEntry, score: Int)] = entries.compactMap { entry in
            guard let score = KnowledgeTextSearch.score(
                query: query, fields: [entry.canonical] + entry.triggers) else { return nil }
            return (entry, score)
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.enabled != rhs.entry.enabled { return lhs.entry.enabled }
            let name = lhs.entry.canonical.localizedCaseInsensitiveCompare(rhs.entry.canonical)
            if name != .orderedSame { return name == .orderedAscending }
            return lhs.entry.id < rhs.entry.id
        }.map(\.entry)
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
            try await repository.deleteLexicon(id: entry.id)
            deleted = entry
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
            return await applyImport(document.entries)
        } catch {
            toast.show("Could not import this file. \(error.localizedDescription)", style: .error)
            return LexiconImportResult()
        }
    }

    /// Deterministic, newline-free plain-text export of user entries.
    public func exportPlainText() -> String {
        LexiconPlainText.encode(entries.filter { $0.source == .user })
    }

    public func importPlainText(_ text: String) async -> LexiconImportResult {
        let parsed = LexiconPlainText.decode(text)
        guard !parsed.records.isEmpty else {
            toast.show(LexiconDocumentError.noEntries.localizedDescription, style: .warning)
            return LexiconImportResult(skipped: parsed.malformed)
        }
        let imported = parsed.records.map { record -> LexiconEntry in
            let isTerm = record.triggers.contains {
                LexiconValidation.normalized($0) == LexiconValidation.normalized(record.canonical)
            }
            return LexiconEntry(kind: isTerm ? .term : .correction,
                                triggers: record.triggers, canonical: record.canonical)
        }
        return await applyImport(imported, extraSkipped: parsed.malformed)
    }

    /// Shared import pipeline for JSON and plain text. Per-row problems are
    /// skipped and counted; a repository failure never mutates local state for
    /// that row.
    private func applyImport(_ incoming: [LexiconEntry],
                             extraSkipped: Int = 0) async -> LexiconImportResult {
        var result = LexiconImportResult(skipped: extraSkipped)
        var known = Set(entries.flatMap { $0.triggers.map(LexiconValidation.normalized) })
        var knownIDs = Set(entries.map(\.id))
        for raw in incoming {
            let draft = LexiconDraft(entry: raw).cleaned
            let keys = draft.triggers.map(LexiconValidation.normalized)
            guard !draft.triggers.isEmpty, !draft.canonical.isEmpty,
                  draft.canonical.count <= LexiconValidation.maxCanonicalLength,
                  draft.triggers.allSatisfy({ $0.count <= LexiconValidation.maxTriggerLength }),
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
    }
}
