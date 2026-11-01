import Foundation
import SQLite3
import SuperflowKernel
import SuperflowPorts

extension SQLiteStore {
    // MARK: helpers

    func runSessionQuery(_ sql: String, values: [SQLValue]) throws -> [SessionRecord] {
        let statement = try db.prepare(sql)
        try statement.bind(values)
        var result: [SessionRecord] = []
        while try statement.step() {
            result.append(Self.session(from: statement))
        }
        return result
    }

    func replaceSearchRow(session: SessionID, index: Int, text: String) throws {
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
