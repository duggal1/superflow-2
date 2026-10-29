import Foundation
import SuperflowKernel
import SuperflowPorts

extension SQLiteStore: LibraryRepository {
    public func lexicon() async throws -> [LexiconEntry] {
        let statement = try db.prepare("""
        SELECT id, kind, triggers, canonical, enabled, source FROM lexicon_entries ORDER BY canonical
        """)
        var result: [LexiconEntry] = []
        while try statement.step() {
            let triggersData = (statement.text(2) ?? "[]").data(using: .utf8) ?? Data()
            let triggers = (try? JSONDecoder().decode([String].self, from: triggersData)) ?? []
            result.append(LexiconEntry(
                id: statement.text(0) ?? "",
                kind: LexiconKind(rawValue: statement.text(1) ?? "") ?? .term,
                triggers: triggers,
                canonical: statement.text(3) ?? "",
                enabled: statement.int(4) != 0,
                source: EntrySource(rawValue: statement.text(5) ?? "") ?? .user))
        }
        return result
    }

    public func saveLexicon(_ e: LexiconEntry) async throws {
        let triggers = String(data: try JSONEncoder().encode(e.triggers), encoding: .utf8) ?? "[]"
        let statement = try db.prepare("""
        INSERT INTO lexicon_entries (id, kind, triggers, canonical, enabled, source)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, triggers = excluded.triggers,
            canonical = excluded.canonical, enabled = excluded.enabled, source = excluded.source
        """)
        try statement.bind([.text(e.id), .text(e.kind.rawValue), .text(triggers), .text(e.canonical),
                            .integer(e.enabled ? 1 : 0), .text(e.source.rawValue)])
        try statement.step()
    }

    public func deleteLexicon(id: String) async throws {
        let statement = try db.prepare("DELETE FROM lexicon_entries WHERE id = ?")
        try statement.bind([.text(id)])
        try statement.step()
    }

    public func shortcuts() async throws -> [ShortcutEntry] {
        let statement = try db.prepare("""
        SELECT id, trigger, content, match, enabled FROM shortcuts ORDER BY trigger
        """)
        var result: [ShortcutEntry] = []
        while try statement.step() {
            result.append(ShortcutEntry(
                id: statement.text(0) ?? "",
                trigger: statement.text(1) ?? "",
                content: statement.text(2) ?? "",
                match: ShortcutMatch(rawValue: statement.text(3) ?? "") ?? .wholeUtterance,
                enabled: statement.int(4) != 0))
        }
        return result
    }

    public func saveShortcut(_ e: ShortcutEntry) async throws {
        let statement = try db.prepare("""
        INSERT INTO shortcuts (id, trigger, content, match, enabled) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET trigger = excluded.trigger, content = excluded.content,
            match = excluded.match, enabled = excluded.enabled
        """)
        try statement.bind([.text(e.id), .text(e.trigger), .text(e.content),
                            .text(e.match.rawValue), .integer(e.enabled ? 1 : 0)])
        try statement.step()
    }

    public func deleteShortcut(id: String) async throws {
        let statement = try db.prepare("DELETE FROM shortcuts WHERE id = ?")
        try statement.bind([.text(id)])
        try statement.step()
    }
}

extension SQLiteStore: SettingsStore {
    private static let settingsKey = "app"

    public func load() async -> AppSettings {
        guard let json = try? db.scalarText("SELECT json FROM settings WHERE key = ?",
                                            [.text(Self.settingsKey)]),
              let data = json.data(using: .utf8) else { return .default }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .default
    }

    public func save(_ s: AppSettings) async {
        guard let data = try? JSONEncoder().encode(s),
              let json = String(data: data, encoding: .utf8) else { return }
        guard let statement = try? db.prepare("""
        INSERT INTO settings (key, json) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET json = excluded.json
        """) else { return }
        try? statement.bind([.text(Self.settingsKey), .text(json)])
        _ = try? statement.step()
    }
}
