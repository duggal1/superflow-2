# Knowledge back end — implementation plan (Agent 5)

Goal: real, complete SQLite-backed knowledge back end. No stubs.

## Non-goals
- No UI edits (Agent 4 owns KnowledgeView/KnowledgeNoticeRouter/FeatureHistory).
- No changes to L0 Ports/Kernel public model shapes (shared currency).
- No new cross-layer dependencies.

## Invariants
- All knowledge writes are idempotent (UPSERT by id) and atomic with their FTS rows.
- Deterministic ordering everywhere: enabled desc, canonical/trigger NOCASE asc, id asc.
- FTS5 is external-content + triggers, so any write path keeps the index in sync.
- Migrations are versioned, transactional, idempotent; v6 backfills FTS via rebuild.
- SQLiteStore actor serializes access; concurrent writers cannot lose rows.
- VMs never mutate local state on a failed repository call; `load()` sets `error`.

## Failure modes covered
- Empty DB, duplicate ids/triggers, invalid/blank input, overlong values,
  unicode/emoji/newlines/quotes, hostile FTS queries, concurrent writes,
  restart/reopen, migration from v1 and v5, repeated migration.

## Ordered steps (each verified by a command)
1. Write failing tests (4 packages) — `swift test` must fail to compile/pass. DONE-basis.
2. Storage: Schema v6 FTS5 + backfill; refactor row mappers; FTS search methods.
3. Storage: make lexicon/shortcut CRUD deterministic; keep transactional FTS sync.
4. FeatureDictionary: search, plain-text codec, honest error states.
5. FeatureShortcuts: search, plain-text codec, honest error states.
6. DictionaryLearningEngine: robust confirm/reject/undo/observe; persistence-friendly.
7. Verify: swift test x4, lint-forbidden, check-deps, release build.
8. Report + completion audit (two clean passes).
