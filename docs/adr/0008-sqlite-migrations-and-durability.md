# ADR 0008: Versioned SQLite migrations, WAL durability, and quarantine

**Status:** Accepted

## Context

`StorageSQLite` is the only durable store for sessions, segments, speakers,
statistics, the lexicon, shortcuts, and settings. Schema v1 shipped with the
first build. A later build needed indexes for the launch recovery scan and for
meeting timelines, and existing v1 databases had to keep their transcripts.

The store also has to survive the failures the plan calls out: a corrupt file,
a failed migration, a crash mid-write, and an upgrade from an older build.

## Decision

- Track the schema with `PRAGMA user_version`. `Schema.migrate` applies each
  version in its own transaction and sets `user_version` inside that transaction,
  so a failed step leaves the previous version intact.
- Never rewrite data in a forward migration unless the data model changes. The
  v1 → v2 migration only adds `sessions_status(status, started_at DESC)` and
  `segments_source(session_id, source)`.
- Freeze a v1 schema in `Tests/StorageSQLiteTests/Fixtures/schema-v1.sql` and
  migrate it in tests. The fixture is the contract with already-installed builds;
  do not edit it when the current schema moves forward.
- Configure every connection with WAL journaling, `synchronous=NORMAL`, foreign
  keys on, a 5 second busy timeout, and in-memory temp storage. WAL keeps a
  crash from losing committed rows and lets a future reader run alongside the
  single writer actor.
- Run `PRAGMA quick_check` before migrating. If the check or migration fails,
  `SQLiteStoreFactory.open` moves the database **and its `-wal`/`-shm` sidecars**
  to `Superflow-corrupt-<timestamp>.sqlite*` and opens a clean database. The
  original bytes are preserved for support rather than deleted.
- Keep the FTS5 `segment_search` table synchronized in the same transaction as
  the segment write. Search queries that SQLite's FTS parser rejects fall back to
  `LIKE` rather than surfacing a database error to the UI.
- Retention deletes only sessions whose status is not `recording` or
  `finalizing`, so a purge at launch cannot delete the session being recovered.

## Consequences and limits

- Migrations are forward-only. A downgrade is not supported; users who need to
  return to an older build must restore a backup.
- Quarantine trades automatic data recovery for availability: the app starts,
  but the quarantined file needs manual inspection. The crash-recovery runbook
  documents the file names.
- One writer actor is deliberate. Adding a reader connection later is allowed by
  WAL but is not implemented.
- The v2 indexes are not a substitute for measuring query plans. If the recovery
  scan or history query becomes slow, add an index in a new version with a new
  frozen fixture, not by editing v2.

## Evidence

`swift test --package-path Packages/L1-Adapters/StorageSQLite`: 24 tests, 0
failures, including:

- `testV1FixtureMigratesForwardAndKeepsRowsAndSearch`
- `testMigrationIsIdempotentAcrossReopen`
- `testFailedMigrationRollsBackAndFactoryQuarantines`
- `testFactoryQuarantinesWALSidecarsWithTheDatabase`
- `testWALAndRuntimePragmasAreEnabled`
- `testFTS5IndexExistsAndSpecialQueriesAreSafe`
- `testDataSurvivesRelaunch`
- `testRetentionPurgeSurvivesRelaunchAndKeepsActiveSessions`
- `testSQLiteSatisfiesTranscriptRepositoryContract`
- `testSQLiteSatisfiesSettingsStoreContract`
