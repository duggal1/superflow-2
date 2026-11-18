import Foundation
import SuperflowKernel
import SuperflowPorts

/// Batch, idempotent writes keyed by the domain's stable identifiers: a
/// session's `id`, a segment's `(session_id, idx)`, a speaker's
/// `(session_id, id)`. Replaying a batch after a crash or a retry updates the
/// same rows instead of duplicating them, which is what makes recovery and
/// re-import safe.
public extension SQLiteStore {
    /// Inserts or updates every segment in one transaction. The FTS row is
    /// replaced in the same transaction, so search cannot disagree with the
    /// base row after a replay.
    func upsertSegments(_ segments: [Segment]) async throws {
        guard !segments.isEmpty else { return }
        try db.transaction {
            for segment in segments {
                let statement = try db.prepare("""
                INSERT INTO segments (session_id, idx, start_ms, end_ms, speaker_id, source,
                                      raw_text, cleaned_text, cleanup_state, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id, idx) DO UPDATE SET
                    start_ms = excluded.start_ms, end_ms = excluded.end_ms,
                    speaker_id = excluded.speaker_id, source = excluded.source,
                    raw_text = excluded.raw_text, cleaned_text = excluded.cleaned_text,
                    cleanup_state = excluded.cleanup_state
                """)
                try statement.bind([
                    .text(segment.sessionID.value), .integer(Int64(segment.index)),
                    .integer(Int64(segment.startMs)), .integer(Int64(segment.endMs)),
                    segment.speakerID.map { .text($0) } ?? .null,
                    .text(segment.source.rawValue), .text(segment.rawText),
                    segment.cleanedText.map { .text($0) } ?? .null,
                    .text(segment.cleanupState.rawValue),
                    .real(segment.createdAt.timeIntervalSince1970),
                ])
                try statement.step()
                try replaceSearchRow(session: segment.sessionID,
                                     index: segment.index, text: segment.bestText)
            }
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    /// Idempotent batch of session upserts. `createSession(_:)` is already a
    /// single-row UPSERT on the stable `id`; the loop only adds transaction
    /// boundaries for a multi-row replay.
    func upsertSessions(_ records: [SessionRecord]) async throws {
        guard !records.isEmpty else { return }
        try db.transaction {
            for record in records {
                let statement = try db.prepare("""
                INSERT INTO sessions (id, kind, started_at, ended_at, status, frontmost_bundle_id,
                                      model_profile, duration_ms, word_count, cleanup_state, title,
                                      local_day, audio_duration, audio_peaks)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind, started_at = excluded.started_at,
                    ended_at = excluded.ended_at, status = excluded.status,
                    frontmost_bundle_id = excluded.frontmost_bundle_id,
                    model_profile = excluded.model_profile, duration_ms = excluded.duration_ms,
                    word_count = excluded.word_count, cleanup_state = excluded.cleanup_state,
                    title = excluded.title, local_day = excluded.local_day,
                    audio_duration = excluded.audio_duration, audio_peaks = excluded.audio_peaks
                """)
                try statement.bind(Self.values(for: record))
                try statement.step()
            }
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }

    /// Idempotent batch of speaker upserts keyed by `(session_id, id)`.
    func upsertSpeakers(_ records: [SpeakerRecord]) async throws {
        guard !records.isEmpty else { return }
        try db.transaction {
            for record in records {
                let statement = try db.prepare("""
                INSERT INTO speakers (session_id, id, label, is_self) VALUES (?, ?, ?, ?)
                ON CONFLICT(session_id, id) DO UPDATE SET
                    label = excluded.label, is_self = excluded.is_self
                """)
                try statement.bind([.text(record.sessionID.value), .text(record.id),
                                    .text(record.label), .integer(record.isSelf ? 1 : 0)])
                try statement.step()
            }
        }
        NotificationCenter.default.post(name: .superflowTranscriptsChanged, object: nil)
    }
}
