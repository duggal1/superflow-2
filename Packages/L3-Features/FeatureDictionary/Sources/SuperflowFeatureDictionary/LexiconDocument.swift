import Foundation
import SuperflowKernel
import SuperflowTextLexicon

/// An editable dictionary entry. `id` is nil for a new entry.
public struct LexiconDraft: Equatable, Sendable {
    public var id: String?
    public var kind: LexiconKind
    public var triggers: [String]
    public var canonical: String
    public var enabled: Bool
    public var source: EntrySource

    public init(id: String? = nil, kind: LexiconKind = .term, triggers: [String] = [""],
                canonical: String = "", enabled: Bool = true, source: EntrySource = .user) {
        self.id = id
        self.kind = kind
        self.triggers = triggers
        self.canonical = canonical
        self.enabled = enabled
        self.source = source
    }

    public init(entry: LexiconEntry) {
        self.init(id: entry.id, kind: entry.kind, triggers: entry.triggers,
                  canonical: entry.canonical, enabled: entry.enabled, source: entry.source)
    }

    public var cleaned: LexiconDraft {
        var copy = self
        copy.triggers = triggers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.canonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    public var entry: LexiconEntry {
        let value = cleaned
        return LexiconEntry(id: id ?? UUID().uuidString, kind: kind, triggers: value.triggers,
                            canonical: value.canonical, enabled: enabled, source: source)
    }
}

public enum LexiconIssue: Hashable, Sendable {
    case missingTrigger
    case missingCanonical
    case duplicateTrigger(String)
    case commonWordTrigger(String)
    case triggerTooLong(String)
    case canonicalTooLong

    public var isBlocking: Bool {
        switch self {
        case .commonWordTrigger: false
        default: true
        }
    }

    public var message: String {
        switch self {
        case .missingTrigger:
            "Add at least one trigger."
        case .missingCanonical:
            "Add the form Superflow should write."
        case .duplicateTrigger(let trigger):
            "“\(trigger)” is already used by another entry."
        case .commonWordTrigger(let trigger):
            "“\(trigger)” is made of common words. It may rewrite ordinary speech."
        case .triggerTooLong(let trigger):
            "“\(trigger)” is longer than 80 characters."
        case .canonicalTooLong:
            "The replacement is longer than 200 characters."
        }
    }
}

public enum LexiconValidation {
    public static let maxTriggerLength = 80
    public static let maxCanonicalLength = 200

    /// Collision key: case, spacing, hyphens and dots are normalized away.
    public static func normalized(_ trigger: String) -> String {
        trigger.lowercased()
            .replacingOccurrences(of: "[\\s.\\-]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func issues(draft: LexiconDraft, existing: [LexiconEntry]) -> [LexiconIssue] {
        let value = draft.cleaned
        var issues: [LexiconIssue] = []
        if value.triggers.isEmpty { issues.append(.missingTrigger) }
        if value.canonical.isEmpty { issues.append(.missingCanonical) }
        if value.canonical.count > maxCanonicalLength { issues.append(.canonicalTooLong) }

        var seen: Set<String> = []
        let others = existing.filter { $0.id != draft.id }
        let otherKeys = Set(others.flatMap { $0.triggers.map(normalized) })
        for trigger in value.triggers {
            let key = normalized(trigger)
            if key.isEmpty { continue }
            if trigger.count > maxTriggerLength { issues.append(.triggerTooLong(trigger)) }
            if !seen.insert(key).inserted { issues.append(.duplicateTrigger(trigger)) }
            if otherKeys.contains(key) { issues.append(.duplicateTrigger(trigger)) }
            if CommonWords.isRisky(trigger: trigger) { issues.append(.commonWordTrigger(trigger)) }
        }
        return issues
    }

    public static func isValid(_ draft: LexiconDraft, existing: [LexiconEntry]) -> Bool {
        !issues(draft: draft, existing: existing).contains(where: \.isBlocking)
    }
}

public struct LexiconDocument: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var entries: [LexiconEntry]

    public init(version: Int = LexiconDocument.currentVersion, entries: [LexiconEntry]) {
        self.version = version
        self.entries = entries
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LexiconDocument {
        let decoder = JSONDecoder()
        do {
            let document = try decoder.decode(LexiconDocument.self, from: data)
            guard document.version <= currentVersion else {
                throw LexiconDocumentError.unsupportedVersion(document.version)
            }
            return document
        } catch let error as LexiconDocumentError {
            throw error
        } catch {
            let entries = try decoder.decode([LexiconEntry].self, from: data)
            return LexiconDocument(entries: entries)
        }
    }
}

public enum LexiconDocumentError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case noEntries

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This file was made by a newer version of Superflow (schema \(version))."
        case .noEntries:
            "The file did not contain any dictionary entries."
        }
    }
}

public struct LexiconImportResult: Sendable, Equatable {
    public var imported: Int
    public var skipped: Int
    public var warnings: [String]

    public init(imported: Int = 0, skipped: Int = 0, warnings: [String] = []) {
        self.imported = imported
        self.skipped = skipped
        self.warnings = warnings
    }

    public var summary: String {
        let base = imported == 1 ? "Imported 1 entry." : "Imported \(imported) entries."
        guard skipped > 0 else { return base }
        return base + " Skipped \(skipped)."
    }
}
