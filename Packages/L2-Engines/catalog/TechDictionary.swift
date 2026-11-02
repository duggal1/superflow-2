import Foundation
import SuperflowKernel

/// Bundled post-ASR technology dictionary, loaded once per process.
///
/// It is consumed only by the final deterministic replacement stage. It must
/// never be passed to the ASR engine or the cleanup model.
public enum TechDictionary {
    public enum Tier: String, Sendable, Decodable { case a = "A", b = "B" }

    public struct Alias: Sendable, Decodable, Equatable {
        public let text: String
        public let tier: Tier
        public let requires: [String]
        public let neg: [String]

        enum CodingKeys: String, CodingKey { case text = "t", tier, requires, neg }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            tier = try container.decode(Tier.self, forKey: .tier)
            requires = try container.decodeIfPresent([String].self, forKey: .requires) ?? []
            neg = try container.decodeIfPresent([String].self, forKey: .neg) ?? []
        }
    }

    public struct Entry: Sendable, Decodable, Equatable {
        public let id: String
        public let canonical: String
        public let kind: String
        public let pack: String
        public let caseStyle: String
        public let aliases: [Alias]
        public let enabledDefault: Bool

        enum CodingKeys: String, CodingKey {
            case id, canonical, kind, pack, aliases
            case caseStyle = "case"
            case enabledDefault = "enabled_default"
        }
    }

    private struct File: Decodable {
        let version: Int
        let entries: [Entry]
    }

    /// Loaded once. A missing or invalid resource yields an empty dictionary.
    public static let entries: [Entry] = load()

    /// Every alias with its owner, keyed by canonical + trigger for the gate.
    public static let rules: [String: Alias] = {
        var rules: [String: Alias] = [:]
        for entry in entries {
            for alias in entry.aliases {
                rules[key(trigger: alias.text, canonical: entry.canonical)] = alias
            }
        }
        return rules
    }()

    public static func rule(trigger: String, canonical: String) -> Alias? {
        rules[key(trigger: trigger, canonical: canonical)]
    }

    /// Flat lexicon entries. Canonical forms are already explicit aliases in
    /// v4, so the stage must not append them a second time.
    public static func lexiconEntries() -> [LexiconEntry] {
        entries.map { entry in
            LexiconEntry(id: entry.id,
                         kind: .term,
                         triggers: entry.aliases.map(\.text),
                         canonical: entry.canonical,
                         // Tier B entries stay in the lexicon; the gate, not
                         // the enabled flag, decides whether they fire.
                         enabled: true,
                         source: .bundled)
        }
    }

    private static func key(trigger: String, canonical: String) -> String {
        canonical + "\u{1}" + trigger
    }

    private static func load() -> [Entry] {
        guard let url = Bundle.module.url(forResource: "vocab_v4", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version == 4 else { return [] }
        return file.entries
    }
}
