-- StorageSQLite schema v1, captured as a fixture for forward-migration tests.
-- Keep this file frozen: it represents a database written by a shipped build.
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
