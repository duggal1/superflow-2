import Foundation

/// Versioned migrations. Each version is applied inside its own transaction so
/// a failed upgrade leaves the previous schema intact.
enum Schema {
    static let currentVersion: Int32 = 3

    static func migrate(_ connection: SQLiteConnection) throws {
        let version = connection.userVersion
        guard version < currentVersion else { return }
        if version < 1 {
            try connection.transaction {
                try connection.execute(v1)
                try connection.setUserVersion(1)
            }
        }
        if version < 2 {
            try connection.transaction {
                try connection.execute(v2)
                try connection.setUserVersion(2)
            }
        }
        if version < 3 {
            try connection.transaction {
                try connection.execute(v3)
                try connection.setUserVersion(3)
            }
        }
    }

    static let v1 = """
    CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        started_at REAL NOT NULL,
        ended_at REAL,
        status TEXT NOT NULL,
        frontmost_bundle_id TEXT,
        model_profile TEXT NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        word_count INTEGER NOT NULL DEFAULT 0,
        cleanup_state TEXT NOT NULL DEFAULT 'pending',
        title TEXT,
        local_day TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS sessions_started ON sessions(started_at DESC);
    CREATE INDEX IF NOT EXISTS sessions_kind ON sessions(kind, started_at DESC);
    CREATE INDEX IF NOT EXISTS sessions_day ON sessions(local_day);

    CREATE TABLE IF NOT EXISTS segments (
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL,
        speaker_id TEXT,
        source TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        cleaned_text TEXT,
        cleanup_state TEXT NOT NULL DEFAULT 'pending',
        created_at REAL NOT NULL,
        PRIMARY KEY (session_id, idx)
    );
    CREATE INDEX IF NOT EXISTS segments_session ON segments(session_id, idx);

    CREATE TABLE IF NOT EXISTS speakers (
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        id TEXT NOT NULL,
        label TEXT NOT NULL,
        is_self INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (session_id, id)
    );

    CREATE TABLE IF NOT EXISTS daily_stats (
        day TEXT PRIMARY KEY NOT NULL,
        words INTEGER NOT NULL DEFAULT 0,
        audio_ms INTEGER NOT NULL DEFAULT 0,
        sessions INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS lexicon_entries (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        triggers TEXT NOT NULL,
        canonical TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        source TEXT NOT NULL DEFAULT 'user'
    );

    CREATE TABLE IF NOT EXISTS shortcuts (
        id TEXT PRIMARY KEY NOT NULL,
        trigger TEXT NOT NULL,
        content TEXT NOT NULL,
        match TEXT NOT NULL DEFAULT 'wholeUtterance',
        enabled INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY NOT NULL,
        json TEXT NOT NULL
    );

    CREATE VIRTUAL TABLE IF NOT EXISTS segment_search USING fts5(
        session_id UNINDEXED,
        idx UNINDEXED,
        text,
        tokenize = 'porter unicode61'
    );
    """

    /// v2 adds indexes used by the launch recovery scan and meeting timelines.
    /// It intentionally does not rewrite data, so a v1 database upgrades in place.
    static let v2 = """
    CREATE INDEX IF NOT EXISTS sessions_status ON sessions(status, started_at DESC);
    CREATE INDEX IF NOT EXISTS segments_source ON segments(session_id, source);
    """

    /// v3 adds the archived dictation clip. Both columns are nullable, so every
    /// existing session stays valid and "no audio" is the absence of a value.
    static let v3 = """
    ALTER TABLE sessions ADD COLUMN audio_duration REAL;
    ALTER TABLE sessions ADD COLUMN audio_peaks BLOB;
    """
}
