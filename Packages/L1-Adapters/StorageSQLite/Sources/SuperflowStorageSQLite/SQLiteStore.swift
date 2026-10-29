import Foundation
import SQLite3
import SuperflowKernel
import SuperflowPorts

/// Serialized SQLite store behind all three persistence ports. One writer actor
/// keeps ordering simple; WAL means readers could be added later without a
/// schema change.
public actor SQLiteStore: TranscriptRepository, AudioMetadataStore {
    let db: SQLiteConnection

    public nonisolated let path: String

    public init(path: String) throws {
        self.path = path
        let connection = try SQLiteConnection(path: path)
        guard try connection.quickCheck() else {
            throw SQLiteError(code: SQLITE_CORRUPT, message: "database failed quick_check", sql: "PRAGMA quick_check")
        }
        try Schema.migrate(connection)
        db = connection
    }

    // MARK: sessions

    public func createSession(_ s: SessionRecord) async throws {
        let sql = """
        INSERT INTO sessions (id, kind, started_at, ended_at, status, frontmost_bundle_id, model_profile,
                              duration_ms, word_count, cleanup_state, title, local_day,
                              audio_duration, audio_peaks)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            kind = excluded.kind, started_at = excluded.started_at, ended_at = excluded.ended_at,
            status = excluded.status, frontmost_bundle_id = excluded.frontmost_bundle_id,
            model_profile = excluded.model_profile, duration_ms = excluded.duration_ms,
            word_count = excluded.word_count, cleanup_state = excluded.cleanup_state,
            title = excluded.title, local_day = excluded.local_day,
            audio_duration = excluded.audio_duration, audio_peaks = excluded.audio_peaks
        """
        let statement = try db.prepare(sql)
        try statement.bind(Self.values(for: s))
        try statement.step()
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    public func appendSegment(_ s: Segment) async throws {
        try db.transaction {
            let sql = """
            INSERT INTO segments (session_id, idx, start_ms, end_ms, speaker_id, source, raw_text,
                                  cleaned_text, cleanup_state, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id, idx) DO UPDATE SET
                start_ms = excluded.start_ms, end_ms = excluded.end_ms, speaker_id = excluded.speaker_id,
                source = excluded.source, raw_text = excluded.raw_text,
                cleaned_text = excluded.cleaned_text, cleanup_state = excluded.cleanup_state
            """
            let statement = try db.prepare(sql)
            try statement.bind([
                .text(s.sessionID.value), .integer(Int64(s.index)), .integer(Int64(s.startMs)),
                .integer(Int64(s.endMs)), s.speakerID.map { .text($0) } ?? .null,
                .text(s.source.rawValue), .text(s.rawText),
                s.cleanedText.map { .text($0) } ?? .null,
                .text(s.cleanupState.rawValue), .real(s.createdAt.timeIntervalSince1970),
            ])
            try statement.step()
            try replaceSearchRow(session: s.sessionID, index: s.index, text: s.bestText)
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    public func updateCleaned(session: SessionID, index: Int, cleaned: String?,
                              state: CleanupState) async throws {
        try db.transaction {
            let update = try db.prepare(
                "UPDATE segments SET cleaned_text = ?, cleanup_state = ? WHERE session_id = ? AND idx = ?")
            try update.bind([cleaned.map { .text($0) } ?? .null, .text(state.rawValue),
                             .text(session.value), .integer(Int64(index))])
            try update.step()

            let raw = try db.prepare("SELECT raw_text FROM segments WHERE session_id = ? AND idx = ?")
            try raw.bind([.text(session.value), .integer(Int64(index))])
            guard try raw.step(), let rawText = raw.text(0) else { return }
            try replaceSearchRow(session: session, index: index, text: cleaned ?? rawText)
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    public func finalizeSession(_ id: SessionID, endedAt: Date, status: SessionStatus, durationMs: Int,
                                wordCount: Int, cleanupState: CleanupState) async throws {
        try db.transaction {
            // The dashboard reads daily_stats. Finalize is the only place a
            // dictation becomes a finished take, so the ledger moves by the
            // difference between what was stored and what is being stored; a
            // retry that rewrites a word count must not count the take twice.
            let previous = try db.prepare("""
            SELECT kind, local_day, status, word_count, duration_ms FROM sessions WHERE id = ?
            """)
            try previous.bind([.text(id.value)])
            var kind: String?
            var day = ""
            var wasOpen = false
            var previousWords = 0
            var previousMs = 0
            if try previous.step() {
                kind = previous.text(0)
                day = previous.text(1) ?? ""
                let previousStatus = previous.text(2) ?? ""
                wasOpen = previousStatus == SessionStatus.recording.rawValue
                    || previousStatus == SessionStatus.finalizing.rawValue
                previousWords = Int(previous.int(3))
                previousMs = Int(previous.int(4))
            }

            let statement = try db.prepare("""
            UPDATE sessions SET ended_at = ?, status = ?, duration_ms = ?, word_count = ?, cleanup_state = ?
            WHERE id = ?
            """)
            try statement.bind([.real(endedAt.timeIntervalSince1970), .text(status.rawValue),
                                .integer(Int64(durationMs)), .integer(Int64(wordCount)),
                                .text(cleanupState.rawValue), .text(id.value)])
            try statement.step()

            if kind == SessionKind.dictation.rawValue, !day.isEmpty {
                try Self.applyDailyDelta(db, day: day,
                                         words: wordCount - previousWords,
                                         audioMs: durationMs - previousMs,
                                         sessions: wasOpen ? 1 : 0)
            }
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    public func sessions(kind: SessionKind?, query: String?, limit: Int, offset: Int) async throws -> [SessionRecord] {
        guard limit > 0 else { return [] }
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var sql = "SELECT \(Self.sessionColumns) FROM sessions WHERE (? IS NULL OR kind = ?)"
        var values: [SQLValue] = [kind.map { .text($0.rawValue) } ?? .null,
                                  kind.map { .text($0.rawValue) } ?? .null]
        if !trimmed.isEmpty {
            sql += " AND (title LIKE ? OR id IN (SELECT session_id FROM segment_search WHERE segment_search MATCH ?))"
            values.append(.text("%\(trimmed)%"))
            values.append(.text(Self.ftsQuery(trimmed)))
        }
        sql += " ORDER BY started_at DESC LIMIT ? OFFSET ?"
        values.append(.integer(Int64(limit)))
        values.append(.integer(Int64(max(0, offset))))

        do {
            return try runSessionQuery(sql, values: values)
        } catch {
            guard !trimmed.isEmpty else { throw error }
            var fallback = "SELECT \(Self.sessionColumns) FROM sessions WHERE (? IS NULL OR kind = ?)"
            var fallbackValues: [SQLValue] = [kind.map { .text($0.rawValue) } ?? .null,
                                              kind.map { .text($0.rawValue) } ?? .null]
            fallback += """
             AND (title LIKE ? OR id IN (SELECT DISTINCT session_id FROM segments
                                         WHERE raw_text LIKE ? OR cleaned_text LIKE ?))
            """
            fallbackValues.append(.text("%\(trimmed)%"))
            fallbackValues.append(.text("%\(trimmed)%"))
            fallbackValues.append(.text("%\(trimmed)%"))
            fallback += " ORDER BY started_at DESC LIMIT ? OFFSET ?"
            fallbackValues.append(.integer(Int64(limit)))
            fallbackValues.append(.integer(Int64(max(0, offset))))
            return try runSessionQuery(fallback, values: fallbackValues)
        }
    }

    public func session(_ id: SessionID) async throws -> SessionRecord? {
        let statement = try db.prepare("SELECT \(Self.sessionColumns) FROM sessions WHERE id = ?")
        try statement.bind([.text(id.value)])
        guard try statement.step() else { return nil }
        return Self.session(from: statement)
    }

    public func segment(session: SessionID, index: Int) async throws -> Segment? {
        let statement = try db.prepare("""
        SELECT session_id, idx, start_ms, end_ms, speaker_id, source, raw_text, cleaned_text,
               cleanup_state, created_at
        FROM segments WHERE session_id = ? AND idx = ?
        """)
        try statement.bind([.text(session.value), .integer(Int64(index))])
        guard try statement.step() else { return nil }
        return Self.segment(from: statement)
    }

    public func segments(session: SessionID) async throws -> [Segment] {
        let statement = try db.prepare("""
        SELECT session_id, idx, start_ms, end_ms, speaker_id, source, raw_text, cleaned_text,
               cleanup_state, created_at
        FROM segments WHERE session_id = ? ORDER BY idx
        """)
        try statement.bind([.text(session.value)])
        var result: [Segment] = []
        while try statement.step() {
            result.append(Self.segment(from: statement))
        }
        return result
    }

    public func transcriptTextForProcessing(session: SessionID) async throws -> String {
        let statement = try db.prepare("""
        SELECT session_id, idx, start_ms, end_ms, speaker_id, source, raw_text, cleaned_text,
               cleanup_state, created_at
        FROM segments WHERE session_id = ? ORDER BY idx
        """)
        try statement.bind([.text(session.value)])
        var text = ""
        while try statement.step() {
            let value = Self.segment(from: statement).bestText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if !text.isEmpty { text.append(contentsOf: "\n\n") }
            text.append(contentsOf: value)
        }
        return text
    }

    public func deleteSession(_ id: SessionID) async throws {
        try db.transaction {
            let search = try db.prepare("DELETE FROM segment_search WHERE session_id = ?")
            try search.bind([.text(id.value)])
            try search.step()
            let statement = try db.prepare("DELETE FROM sessions WHERE id = ?")
            try statement.bind([.text(id.value)])
            try statement.step()
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    // MARK: speakers

    public func upsertSpeaker(_ s: SpeakerRecord) async throws {
        let statement = try db.prepare("""
        INSERT INTO speakers (session_id, id, label, is_self) VALUES (?, ?, ?, ?)
        ON CONFLICT(session_id, id) DO UPDATE SET label = excluded.label, is_self = excluded.is_self
        """)
        try statement.bind([.text(s.sessionID.value), .text(s.id), .text(s.label),
                            .integer(s.isSelf ? 1 : 0)])
        try statement.step()
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    public func speakers(session: SessionID) async throws -> [SpeakerRecord] {
        let statement = try db.prepare(
            "SELECT session_id, id, label, is_self FROM speakers WHERE session_id = ? ORDER BY id")
        try statement.bind([.text(session.value)])
        var result: [SpeakerRecord] = []
        while try statement.step() {
            result.append(SpeakerRecord(sessionID: SessionID(statement.text(0) ?? session.value),
                                        id: statement.text(1) ?? "",
                                        label: statement.text(2) ?? "",
                                        isSelf: statement.int(3) != 0))
        }
        return result
    }

    public func renameSession(_ id: SessionID, title: String) async throws {
        let statement = try db.prepare("UPDATE sessions SET title = ? WHERE id = ?")
        try statement.bind([.text(title), .text(id.value)])
        try statement.step()
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    public func renameSpeaker(session: SessionID, id: String, label: String) async throws {
        let statement = try db.prepare("UPDATE speakers SET label = ? WHERE session_id = ? AND id = ?")
        try statement.bind([.text(label), .text(session.value), .text(id)])
        try statement.step()
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    // MARK: stats and maintenance

    public func dailyStats(fromDay: String, toDay: String) async throws -> [DailyStat] {
        let statement = try db.prepare("""
        SELECT day, words, audio_ms, sessions FROM daily_stats
        WHERE day >= ? AND day <= ? ORDER BY day
        """)
        try statement.bind([.text(fromDay), .text(toDay)])
        var result: [DailyStat] = []
        while try statement.step() {
            result.append(DailyStat(day: statement.text(0) ?? "",
                                    words: Int(statement.int(1)),
                                    audioMs: Int(statement.int(2)),
                                    sessions: Int(statement.int(3))))
        }
        return result
    }

    public func addDailyStat(_ s: DailyStat) async throws {
        try Self.applyDailyDelta(db, day: s.day, words: s.words,
                                 audioMs: s.audioMs, sessions: s.sessions)
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    /// Moves one day's ledger row by a delta. Shared by `addDailyStat` and the
    /// finalize path so both write the same row shape.
    static func applyDailyDelta(_ db: SQLiteConnection, day: String,
                                words: Int, audioMs: Int, sessions: Int) throws {
        guard words != 0 || audioMs != 0 || sessions != 0 else { return }
        let statement = try db.prepare("""
        INSERT INTO daily_stats (day, words, audio_ms, sessions) VALUES (?, ?, ?, ?)
        ON CONFLICT(day) DO UPDATE SET
            words = words + excluded.words,
            audio_ms = audio_ms + excluded.audio_ms,
            sessions = sessions + excluded.sessions
        """)
        try statement.bind([.text(day), .integer(Int64(words)),
                            .integer(Int64(audioMs)), .integer(Int64(sessions))])
        try statement.step()
    }

    public func unfinishedSessions() async throws -> [SessionRecord] {
        let statement = try db.prepare("""
        SELECT \(Self.sessionColumns) FROM sessions
        WHERE status IN ('recording', 'finalizing') ORDER BY started_at
        """)
        var result: [SessionRecord] = []
        while try statement.step() {
            result.append(Self.session(from: statement))
        }
        return result
    }

    public func purge(olderThan: Date) async throws -> Int {
        let select = try db.prepare("""
        SELECT id, kind, local_day, word_count, duration_ms FROM sessions
        WHERE started_at < ? AND status NOT IN ('recording', 'finalizing')
        """)
        try select.bind([.real(olderThan.timeIntervalSince1970)])
        var purged: [(id: SessionID, kind: String, day: String, words: Int, audioMs: Int)] = []
        while try select.step() {
            guard let id = select.text(0) else { continue }
            purged.append((SessionID(id), select.text(1) ?? "", select.text(2) ?? "",
                           Int(select.int(3)), Int(select.int(4))))
        }
        guard !purged.isEmpty else { return 0 }
        try db.transaction {
            for entry in purged {
                let search = try db.prepare("DELETE FROM segment_search WHERE session_id = ?")
                try search.bind([.text(entry.id.value)])
                try search.step()
                let delete = try db.prepare("DELETE FROM sessions WHERE id = ?")
                try delete.bind([.text(entry.id.value)])
                try delete.step()
                if entry.kind == SessionKind.dictation.rawValue, !entry.day.isEmpty {
                    try Self.applyDailyDelta(db, day: entry.day, words: -entry.words,
                                             audioMs: -entry.audioMs, sessions: -1)
                }
            }
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
        return purged.count
    }

    public func sessionCount(kind: SessionKind?) async throws -> Int {
        let statement = try db.prepare("SELECT COUNT(*) FROM sessions WHERE (? IS NULL OR kind = ?)")
        try statement.bind([kind.map { .text($0.rawValue) } ?? .null,
                            kind.map { .text($0.rawValue) } ?? .null])
        guard try statement.step() else { return 0 }
        return Int(statement.int(0))
    }

    // MARK: helpers

    private func runSessionQuery(_ sql: String, values: [SQLValue]) throws -> [SessionRecord] {
        let statement = try db.prepare(sql)
        try statement.bind(values)
        var result: [SessionRecord] = []
        while try statement.step() {
            result.append(Self.session(from: statement))
        }
        return result
    }

    private func replaceSearchRow(session: SessionID, index: Int, text: String) throws {
        let delete = try db.prepare("DELETE FROM segment_search WHERE session_id = ? AND idx = ?")
        try delete.bind([.text(session.value), .integer(Int64(index))])
        try delete.step()
        let insert = try db.prepare("INSERT INTO segment_search (session_id, idx, text) VALUES (?, ?, ?)")
        try insert.bind([.text(session.value), .integer(Int64(index)), .text(text)])
        try insert.step()
    }

    static func ftsQuery(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace })
            .map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " ")
    }

    static let sessionColumns = """
    id, kind, started_at, ended_at, status, frontmost_bundle_id, model_profile,
    duration_ms, word_count, cleanup_state, title, local_day, audio_duration, audio_peaks,
    (SELECT COALESCE(cleaned_text, raw_text) FROM segments
     WHERE segments.session_id = sessions.id ORDER BY idx LIMIT 1)
    """

    static func values(for s: SessionRecord) -> [SQLValue] {
        [
            .text(s.id.value), .text(s.kind.rawValue), .real(s.startedAt.timeIntervalSince1970),
            s.endedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
            .text(s.status.rawValue), s.frontmostBundleID.map { .text($0) } ?? .null,
            .text(s.modelProfile), .integer(Int64(s.durationMs)), .integer(Int64(s.wordCount)),
            .text(s.cleanupState.rawValue), s.title.map { .text($0) } ?? .null, .text(s.localDay),
            s.audioDuration.map { .real($0) } ?? .null, s.audioPeaks.map { .blob($0) } ?? .null,
        ]
    }

    static func session(from statement: SQLiteStatement) -> SessionRecord {
        SessionRecord(
            id: SessionID(statement.text(0) ?? ""),
            kind: SessionKind(rawValue: statement.text(1) ?? "") ?? .dictation,
            startedAt: Date(timeIntervalSince1970: statement.double(2)),
            endedAt: statement.isNull(3) ? nil : Date(timeIntervalSince1970: statement.double(3)),
            status: SessionStatus(rawValue: statement.text(4) ?? "") ?? .complete,
            frontmostBundleID: statement.text(5),
            modelProfile: statement.text(6) ?? ModelProfile.parakeetEOU120M.id,
            durationMs: Int(statement.int(7)),
            wordCount: Int(statement.int(8)),
            cleanupState: CleanupState(rawValue: statement.text(9) ?? "") ?? .pending,
            title: statement.text(10),
            localDay: statement.text(11) ?? "",
            audioDuration: statement.isNull(12) ? nil : statement.double(12),
            audioPeaks: statement.data(13),
            preview: statement.text(14))
    }

}
