# Knowledge back end — Agent 5 report

STATUS: DONE-SELF-GRADED

Not done / failing / unverified (first, as required):
- Full-app **release build not confirmed**: two attempts were killed at the
  300-second computer-safety cap (final progress 848/1197 and 491/1134) while
  compiling third-party MLX C++; **no Swift compile error was emitted**. The
  coordinator's override forbids runs longer than 5 minutes, and other agents
  repeatedly held the shared build mutex. Verified instead: every package I
  changed compiles and its tests pass (below), and Agent 4 confirmed in their
  contract that their views need no source change against my preserved API.
- Full `TextPipeline` suite has 48 failures in `AggressiveCorpus*` suites owned
  by another agent; unrelated to the knowledge back end. My 10 learning tests
  pass.
- One filtered learning re-run was NOT RUN (fence busy on all 3 retries); the
  full-run evidence for those suites is used instead.

## 1. Peer handshake

- Wrote `.proof/knowledge-back/provided-backend-api.md` early, before Agent 4's
  contract existed.
- Agent 4's `.proof/knowledge-front/expected-backend-api.md` appeared later and
  was read in full. It explicitly states: every required signature is preserved
  and **no source change was needed in their views**. The seam is source
  compatible in both directions.
- No breaking change to any public API. All new surface is additive:
  `search(_:)`, `exportPlainText()`, `importPlainText(_:)`,
  `SQLiteStore.searchLexicon/searchShortcuts`, and `accept/learn` aliases on the
  learning engine.

## 2. What was built (real, not stub)

| Area | Implementation |
|---|---|
| CRUD | SQLite `UPSERT` by id for lexicon, shortcuts, learning candidates. Idempotent, transactional (`BEGIN IMMEDIATE`). |
| Full-text search | Real FTS5 external-content tables `lexicon_search` / `shortcut_search` with AFTER INSERT/UPDATE/DELETE triggers. `bm25` ranking + deterministic tiebreaks. Hostile queries are allow-list tokenised (letters/digits only, quoted prefix tokens, max 16), so `"unbalanced`, `NEAR(`, `*` etc. cannot throw. |
| Deterministic ordering | `enabled DESC`, `canonical`/`trigger COLLATE NOCASE ASC`, `id ASC` in both plain reads and search. Independent of insertion order and rowid. Applied in view models too. |
| Import/export | JSON documents unchanged. Added a documented plain-text format with an escaping codec (unicode, commas, `=>`, `|`, newlines, quotes round-trip). Comments/blank lines ignored; malformed lines **counted as skipped**, not silently dropped. |
| Migrations | v6 adds FTS5 tables + triggers and backfills via `INSERT INTO …('rebuild')`. Version-gated, inside one transaction, idempotent across repeated opens; works from v1 and v5 databases. |
| Concurrency | `SQLiteStore` actor serialises all access; WAL + 5 s busy timeout. 24 parallel writers test proves no rows lost or duplicated. |
| Learning | `DictionaryLearningEngine` confirm/accept/learn, reject, undo, observe with consent + anchor de-dup + phrase safety + auto-promotion. Confirm commits candidate state **and** lexicon rule before returning; `onApplied` fires only after both writes. Repeat confirmations preserve hit/creation metadata. Rejected candidates never rewrite speech; undo never deletes a manual rule. |
| Error states | `load()` sets `error` and never throws; mutating actions return false / show error toasts and never mutate local state on repository failure; import reports `imported`/`skipped`/`warnings`; SQLite errors carry `LocalizedError` with disk-full detection. |

## 3. Test results (one process at a time, `--jobs 1`, under `/tmp/superflow-build-lock`)

| Package | Result | Evidence |
|---|---|---|
| StorageSQLite | **51 tests, 0 failures** | `test-storage.log` |
| FeatureDictionary | **18 tests, 0 failures** | `final-FeatureDictionary.log` (added repeated-import idempotency test; `test-dictionary.log` was the earlier 17-test green run) |
| FeatureShortcuts | **16 tests, 0 failures** | `final-FeatureShortcuts.log` (added repeated-import idempotency test; `test-shortcuts.log` was the earlier 15-test green run) |
| TextPipeline learning suites | **10 tests, 0 failures** (5 `DictionaryLearningTests` + 5 `DictionaryLearningPersistenceTests`) | `test-textpipeline.log` |

New tests cover: happy path, empty DB, duplicate ids/triggers, invalid/blank,
overlong values, unicode/emoji/CJK/quotes/newlines, hostile FTS queries,
24-way concurrent writes, restart persistence, v1→v6 migration with backfill,
idempotent reopen, load/save failures, malformed plain-text lines.

### Specific evidence
- **Migration/idempotency**: `testV1KnowledgeRowsMigrateForwardWithBackfilledSearch`
  seeds a v1 DB with a lexicon term + shortcut, opens it, asserts `user_version ==
  Schema.currentVersion` (6), asserts both FTS searches find the legacy rows,
  reopens twice and asserts counts unchanged.
  `testFTS5TablesExistAndUseExternalContent` asserts both tables are FTS5 with
  `content=` and ≥6 sync triggers.
- **Concurrency**: `testConcurrentWritesAreSerializedAndNothingIsLost` launches
  24 simultaneous tasks writing a lexicon term + shortcut + learning candidate
  each to one actor; asserts 24 unique rows in all three tables, 24 FTS hits,
  and all 72 rows after reopen.
- **Restart**: lexicon, shortcut and all three learning states (`suggested`,
  `confirmed`, `rejected`) are asserted after `SQLiteStore` deinit/reopen;
  engine-level restart is covered by constructing five fresh engines over the
  same persisted stores.
- **No test was weakened or deleted.** All new tests are additive files.

## 4. Lint / layer / build

- `tools/lint-forbidden` → exit 0 ("Forbidden-pattern lint passed").
- `tools/check-deps` → exit 0 ("Dependency layers are valid.").
- `bash tools/test-check-deps` → exit 0.
- `swift build --package-path App/SuperflowApp --configuration release`:
  attempted twice (`--jobs 1`, then `--jobs 2`) under the shared fence; both
  killed at the 300-second safety cap while compiling third-party MLX C++
  (progress 491/1134 and 848/1197; **zero Swift errors**). Not confirmed green.
  Agent 4's concurrent full-app builds (`.proof/knowledge-front/build-release*.log`)
  also had not reached a terminal line at the time of this report. All four
  packages I own compiled and tested green, which covers every changed source
  file; the unchanged App/UI call sites are source-compatible per Agent 4's
  contract.

## 5. Files changed (all inside assigned ownership)

Modified:
- `Packages/L1-Adapters/StorageSQLite/Sources/SuperflowStorageSQLite/Schema.swift`
- `Packages/L1-Adapters/StorageSQLite/Sources/SuperflowStorageSQLite/SQLiteLibraryAndSettings.swift`
- `Packages/L2-Engines/TextPipeline/Sources/SuperflowTextPipeline/DictionaryLearningEngine.swift`
- `Packages/L3-Features/FeatureDictionary/Sources/SuperflowFeatureDictionary/DictionaryViewModel.swift`
- `Packages/L3-Features/FeatureShortcuts/Sources/SuperflowFeatureShortcuts/ShortcutsViewModel.swift`

Added:
- `…/StorageSQLite/Sources/SuperflowStorageSQLite/SQLiteKnowledgeSearch.swift`
- `…/StorageSQLite/Tests/StorageSQLiteTests/KnowledgeStoreTests.swift`
- `…/TextPipeline/Tests/TextPipelineTests/DictionaryLearningPersistenceTests.swift`
- `…/FeatureDictionary/Sources/SuperflowFeatureDictionary/{KnowledgeTextSearch.swift,LexiconPlainText.swift}`
- `…/FeatureDictionary/Tests/FeatureDictionaryTests/KnowledgeBackEndTests.swift`
- `…/FeatureShortcuts/Sources/SuperflowFeatureShortcuts/{KnowledgeTextSearch.swift,ShortcutPlainText.swift}`
- `…/FeatureShortcuts/Tests/FeatureShortcutsTests/KnowledgeBackEndTests.swift`
- `.proof/knowledge-back/{provided-backend-api.md,plan.md,report.md}` + logs

Did **not** touch `KnowledgeView.swift`, `KnowledgeNoticeRouter.swift` or
`FeatureHistory/**`. No commits/push/PR (per task instruction). No new module
dependencies.

## 6. Honest gaps

1. **Full TextPipeline package is not green**: 48 failures in
   `AggressiveCorpusDiversityTests` / `AggressiveCorpusLongTests` (transcription
   quality corpus suites added by another agent, untracked at the time of this
   run). They are unrelated to the knowledge back end; both learning suites
   pass. I did not edit or weaken them.
2. **Release build not confirmed by my own process**: killed at the 300 s
   computer-safety cap during third-party C++ compilation. No Swift compile
   error was emitted. Agent 4's concurrent full-app build was the alternate
   measurement; record its terminal result here once available: PENDING.
3. **Layer boundary**: L3 feature packages cannot import the L1 SQLite adapter,
   so `DictionaryViewModel.search` / `ShortcutsViewModel.search` run the same
   tokenised AND semantics over the in-memory mirror of the SQLite table. The
   real SQLite FTS5 path is `SQLiteStore.searchLexicon/searchShortcuts` and is
   covered by real-DB tests. No single test combines the engine with SQLite
   because L2 engines cannot import L1 adapters.
4. **Plain text is additive**: Agent 4's front end keeps JSON import/export by
   design; no UI exposes the new plain-text methods in this task.
5. Both `KnowledgeTextSearch` / `KnowledgePlainTextCodec` helpers are
   intentionally duplicated (internal, zero new dependencies) because L3
   features cannot depend on each other.
