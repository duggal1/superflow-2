import Foundation
import SuperflowKernel

/// Loads and validates the curated tech dictionary. The bundled file is small
/// by design (at most 150 entries) and every entry carries negative examples.
public enum BundledLexicon {
    public struct Entry: Sendable, Equatable {
        public let canonical: String
        public let kind: LexiconKind
        public let triggers: [String]
        public let negatives: [String]
        public init(canonical: String, kind: LexiconKind, triggers: [String], negatives: [String]) {
            self.canonical = canonical
            self.kind = kind
            self.triggers = triggers
            self.negatives = negatives
        }
    }

    struct File: Decodable {
        struct RawEntry: Decodable {
            let canonical: String
            let kind: String
            let triggers: [String]
            let negatives: [String]
        }
        let schemaVersion: Int
        let entries: [RawEntry]
    }

    public static let maxEntries = 150

    private static let file: File? = {
        guard let url = Bundle.module.url(forResource: "tech-dictionary.v1", withExtension: "json",
                                          subdirectory: "Resources"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    public static func entries() -> [Entry] {
        guard let file else { return [] }
        return file.entries.map { raw in
            Entry(canonical: raw.canonical,
                  kind: raw.kind == LexiconKind.correction.rawValue ? .correction : .term,
                  triggers: raw.triggers,
                  negatives: raw.negatives)
        }
    }

    public static func load() -> [LexiconEntry] {
        entries().map { entry in
            LexiconEntry(id: "bundled:" + entry.canonical,
                         kind: entry.kind,
                         triggers: entry.triggers,
                         canonical: entry.canonical,
                         enabled: true,
                         source: .bundled)
        }
    }

    public static func falsePositiveCorpus() -> [String] {
        guard let url = Bundle.module.url(forResource: "false-positive-corpus", withExtension: "txt",
                                          subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// CI gate: returns every schema or content problem in the bundled file.
    public static func validate() -> [String] {
        guard let file else { return ["bundled dictionary is missing or not valid JSON"] }
        var problems: [String] = []
        if file.schemaVersion != 2 {
            problems.append("schemaVersion must be 2, found \(file.schemaVersion)")
        }
        if file.entries.count > maxEntries {
            problems.append("dictionary has \(file.entries.count) entries; maximum is \(maxEntries)")
        }
        var canonicals = Set<String>()
        var triggerOwners: [String: String] = [:]
        for raw in file.entries {
            if raw.canonical.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("entry with an empty canonical form")
            }
            if !canonicals.insert(raw.canonical).inserted {
                problems.append("duplicate canonical form \"\(raw.canonical)\"")
            }
            if raw.kind != LexiconKind.term.rawValue && raw.kind != LexiconKind.correction.rawValue {
                problems.append("entry \"\(raw.canonical)\" has unknown kind \"\(raw.kind)\"")
            }
            if raw.triggers.isEmpty {
                problems.append("entry \"\(raw.canonical)\" has no triggers")
            }
            if raw.negatives.isEmpty {
                problems.append("entry \"\(raw.canonical)\" has no negative examples")
            }
            for trigger in raw.triggers {
                let key = LexiconNormalizer.key(trigger)
                if key.isEmpty {
                    problems.append("entry \"\(raw.canonical)\" has a trigger that normalizes to nothing")
                    continue
                }
                if let owner = triggerOwners[key], owner != raw.canonical {
                    problems.append("trigger \"\(trigger)\" is shared by \"\(owner)\" and \"\(raw.canonical)\"")
                } else {
                    triggerOwners[key] = raw.canonical
                }
            }
        }
        return problems
    }
}

/// Small high-frequency English list used for dictionary collision warnings.
public enum CommonWords {
    public static let list: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with",
        "he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up", "out", "if",
        "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time", "no", "just", "him",
        "know", "take", "people", "into", "year", "your", "good", "some", "could", "them", "see", "other", "than",
        "then", "now", "look", "only", "come", "its", "over", "think", "also", "back", "after", "use", "two", "how",
        "our", "work", "first", "well", "way", "even", "new", "want", "because", "any", "these", "give", "day",
        "most", "us", "next", "years", "last", "type", "open", "chat", "git", "lab", "hub", "node", "script",
        "scripts", "code", "java", "swift", "react", "query", "stack", "base", "web", "socket", "mac", "fluid",
        "audio", "huge", "icon", "icons", "home", "brew", "test", "flight", "cloud", "kit", "air", "pods",
        "post", "man", "data", "dog", "story", "book", "photo", "shop", "cocoa", "fire", "assembly", "user",
        "defaults", "rest", "search", "elastic", "web", "pack", "roll", "up", "go", "lang", "view", "native",
        "core", "mail", "store", "connect", "grand", "central", "dispatch", "package", "manager",
    ]

    /// True when every word of the trigger is an ordinary English word.
    public static func isRisky(trigger: String) -> Bool {
        let words = trigger.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return !words.isEmpty && words.allSatisfy { list.contains($0) }
    }
}
