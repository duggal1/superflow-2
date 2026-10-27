import Foundation
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowTextShortcuts

public struct ShortcutDraft: Equatable, Sendable {
    public var id: String?
    public var trigger: String
    public var content: String
    public var match: ShortcutMatch
    public var enabled: Bool

    public init(id: String? = nil, trigger: String = "", content: String = "",
                match: ShortcutMatch = .wholeUtterance, enabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.content = content
        self.match = match
        self.enabled = enabled
    }

    public init(entry: ShortcutEntry) {
        self.init(id: entry.id, trigger: entry.trigger, content: entry.content,
                  match: entry.match, enabled: entry.enabled)
    }

    public var entry: ShortcutEntry {
        ShortcutEntry(id: id ?? UUID().uuidString,
                      trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
                      content: content, match: match, enabled: enabled)
    }

    public var contentBytes: Int { content.utf8.count }
}

public enum ShortcutIssue: Hashable, Sendable {
    case missingTrigger
    case missingContent
    case triggerTooLong(String)
    case contentTooLarge(Int)
    case duplicateTrigger(String)
    case commonWordTrigger(String)

    public var isBlocking: Bool {
        switch self {
        case .commonWordTrigger: false
        default: true
        }
    }

    public var message: String {
        switch self {
        case .missingTrigger:
            "Add the words you will say."
        case .missingContent:
            "Add the text this shortcut should insert."
        case .triggerTooLong(let trigger):
            "“\(trigger)” is longer than 80 characters."
        case .contentTooLarge(let bytes):
            "The content is \(bytes / 1024) KB. The limit is 200 KB."
        case .duplicateTrigger(let trigger):
            "“\(trigger)” is already used by another shortcut."
        case .commonWordTrigger(let trigger):
            "“\(trigger)” is made of common words. It may fire during ordinary speech."
        }
    }
}

public enum ShortcutValidation {
    public static let maxTriggerLength = 80

    public static func normalized(_ trigger: String) -> String {
        ShortcutsStage.normalize(trigger)
    }

    public static func issues(draft: ShortcutDraft, existing: [ShortcutEntry]) -> [ShortcutIssue] {
        var issues: [ShortcutIssue] = []
        let trigger = draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if trigger.isEmpty { issues.append(.missingTrigger) }
        if draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingContent)
        }
        if trigger.count > maxTriggerLength { issues.append(.triggerTooLong(trigger)) }
        if draft.contentBytes > ShortcutsStage.maxContentBytes {
            issues.append(.contentTooLarge(draft.contentBytes))
        }
        let key = normalized(trigger)
        if !key.isEmpty {
            let others = existing.filter { $0.id != draft.id }
            if others.contains(where: { normalized($0.trigger) == key }) {
                issues.append(.duplicateTrigger(trigger))
            }
            if CommonWords.isRisky(trigger: trigger) {
                issues.append(.commonWordTrigger(trigger))
            }
        }
        return issues
    }

    public static func isValid(_ draft: ShortcutDraft, existing: [ShortcutEntry]) -> Bool {
        !issues(draft: draft, existing: existing).contains(where: \.isBlocking)
    }
}

public struct ShortcutDocument: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var entries: [ShortcutEntry]

    public init(version: Int = ShortcutDocument.currentVersion, entries: [ShortcutEntry]) {
        self.version = version
        self.entries = entries
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ShortcutDocument {
        let decoder = JSONDecoder()
        do {
            let document = try decoder.decode(ShortcutDocument.self, from: data)
            guard document.version <= currentVersion else {
                throw ShortcutDocumentError.unsupportedVersion(document.version)
            }
            return document
        } catch let error as ShortcutDocumentError {
            throw error
        } catch {
            let entries = try decoder.decode([ShortcutEntry].self, from: data)
            return ShortcutDocument(entries: entries)
        }
    }
}

public enum ShortcutDocumentError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case noEntries

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This file was made by a newer version of Superflow (schema \(version))."
        case .noEntries:
            "The file did not contain any shortcuts."
        }
    }
}

public struct ShortcutImportResult: Sendable, Equatable {
    public var imported: Int
    public var skipped: Int
    public var warnings: [String]

    public init(imported: Int = 0, skipped: Int = 0, warnings: [String] = []) {
        self.imported = imported
        self.skipped = skipped
        self.warnings = warnings
    }

    public var summary: String {
        let base = imported == 1 ? "Imported 1 shortcut." : "Imported \(imported) shortcuts."
        guard skipped > 0 else { return base }
        return base + " Skipped \(skipped)."
    }
}
