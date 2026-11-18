import Foundation
import SuperflowKernel

extension SQLiteStore {
    /// Real SQLite FTS5 search over the knowledge tables. The FTS tables are
    /// external-content tables maintained by triggers (Schema.v6), so a result
    /// can never disagree with the base row.
    ///
    /// Query building is deliberately allow-list based: only letters and digits
    /// survive, each becomes a quoted prefix token, and at most 16 tokens are
    /// used. Hostile strings such as `"unbalanced`, `NEAR(`, `*` or `a OR` can
    /// therefore never become FTS operators or throw.
    static func knowledgeFTSQuery(_ raw: String) -> String? {
        let tokens = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(16)
            .map { token -> String in
                let escaped = String(token).replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
        guard !tokens.isEmpty else { return nil }
        return tokens.joined(separator: " ")
    }

    private static let qualifiedLexiconColumns = """
    lexicon_entries.id, lexicon_entries.kind, lexicon_entries.triggers,
    lexicon_entries.canonical, lexicon_entries.enabled, lexicon_entries.source,
    lexicon_entries.app_scope, lexicon_entries.heard_forms, lexicon_entries.phonetic_key,
    lexicon_entries.learned_from, lexicon_entries.confidence,
    lexicon_entries.confirmation_count, lexicon_entries.hit_count,
    lexicon_entries.created_at, lexicon_entries.updated_at
    """

    /// Full-text search with SQLite ranking, then the same deterministic
    /// tiebreakers as `lexicon()`. Capped so a single query can never read an
    /// unbounded number of rows.
    public func searchLexicon(query: String, limit: Int = 200) async throws -> [LexiconEntry] {
        guard limit > 0, let match = Self.knowledgeFTSQuery(query) else { return [] }
        let capped = min(limit, 500)
        let statement = try db.prepare("""
        SELECT \(Self.qualifiedLexiconColumns)
        FROM lexicon_search
        JOIN lexicon_entries ON lexicon_entries.rowid = lexicon_search.rowid
        WHERE lexicon_search MATCH ?
        ORDER BY bm25(lexicon_search), lexicon_entries.enabled DESC,
                 lexicon_entries.canonical COLLATE NOCASE ASC, lexicon_entries.id ASC
        LIMIT ?
        """)
        try statement.bind([.text(match), .integer(Int64(capped))])
        var result: [LexiconEntry] = []
        while try statement.step() { result.append(Self.lexiconEntry(from: statement)) }
        return result
    }

    public func searchShortcuts(query: String, limit: Int = 200) async throws -> [ShortcutEntry] {
        guard limit > 0, let match = Self.knowledgeFTSQuery(query) else { return [] }
        let capped = min(limit, 500)
        // The FTS table declares "trigger", so qualify every base column.
        let columns = """
        shortcuts.id, shortcuts.trigger, shortcuts.content, shortcuts.match, shortcuts.enabled
        """
        let statement = try db.prepare("""
        SELECT \(columns)
        FROM shortcut_search
        JOIN shortcuts ON shortcuts.rowid = shortcut_search.rowid
        WHERE shortcut_search MATCH ?
        ORDER BY bm25(shortcut_search), shortcuts.enabled DESC,
                 shortcuts.trigger COLLATE NOCASE ASC, shortcuts.id ASC
        LIMIT ?
        """)
        try statement.bind([.text(match), .integer(Int64(capped))])
        var result: [ShortcutEntry] = []
        while try statement.step() { result.append(Self.shortcutEntry(from: statement)) }
        return result
    }
}
