# RecoveryEngine crash-recovery hardening — evidence report

STATUS: DONE — all 37 aggressive package tests pass in debug and release (two consecutive clean audit passes); lint clean; my own fenced app release build is green.

## Scope

Owned and changed only:
- `Packages/L2-Engines/RecoveryEngine/Sources/SuperflowRecoveryEngine/*`
- `Packages/L2-Engines/RecoveryEngine/Tests/RecoveryEngineTests/*`
- `.proof/recovery/*`

No app sources, other packages, tests outside the package, or git commits were touched.

## Failure-mode matrix — BEFORE → AFTER

Evidence for the "before" column is in `.proof/recovery/audit-notes.md` (file/line references from the original code and the L1 journal adapters).

| # | Failure mode | Before | After |
|---|---|---|---|
| F1 | Crash after some segments committed, before finalize | Re-derive resume point from millisecond-truncated `endMs`; ASR timestamps restarted at 0 on replay; no exact commit record | `RecoveryLedger` `.watermark` records exact absolute sample position per source; `RecoverySupport.absolute()` shifts replayed ASR times onto the session clock; `isDuplicate()` suppresses re-appended rows; crash-after-first-append is tested |
| F2 | Crash between finalize and journal deletion | Session no longer unfinished; journal orphaned forever, unreported | `.finalized` is written to the checksummed ledger *before* deletion; `sweepOrphans()` finishes only finalized+terminal sessions and records a `RecoveryDiscarded` entry; unfinalized orphans are kept and reported as `needsUserAction` |
| F3 | Truncated/corrupt journal manifest or PCM | Corrupt lines and missing PCM silently skipped; samples vanish | Recovery ledger is frame+checksum validated per record; damaged records counted in `RecoveryLedgerIntegrity`, moved to `Quarantine/` (never deleted) and surfaced in the report. L1 journal bytes are still parsed by L1's own adapter (see UNVERIFIED) |
| F4 | No version / no checksum on recovery state | Plain JSONL, no magic/version | Framed `SFRL` v1 records with length, sequence and FNV-1a checksum; unknown versions reported as `versionMismatch`, not applied |
| F5 | Two apps recovering concurrently | No lock; duplicate rows possible | `RecoveryLock`: atomic `mkdir`, owner record, busy detection; concurrent test proves exactly one winner and no duplicate rows |
| F6 | Stale lock after process kill | n/a | Lock owner PID liveness (`kill(pid,0)`) + heartbeat age + missing-owner startup grace; stale locks are renamed to `.stale-...` as evidence, never deleted; live owner is never broken |
| F7 | Disk-full mid-write | Partial segment set, no structured signal | **Real bug fixed:** a failed append used to still record the watermark, so retries skipped the lost audio forever. Watermark now advances only after every row commits; failure keeps journal + session `recording` and adds `needsUserAction`; retry succeeds with no data loss |
| F8 | ASR failure / model missing | Free-text notice only | Journal retained; `failed` plus structured `needsUserAction` (including `interrupted` at stream/replay crash points) and truthful notices |
| F9 | Journal claims samples but replay yields none | Session finalized `.recovered` with zero audio | Detected via `replayedSamples == 0` while `total > fromSample`: `needsUserAction` reason `unreadable-journal`, journal kept, session left `recording` |
| F10 | Unbounded recovery time | No deadline | Cooperative budget checked between stages and per replay chunk (clock injectable); timeout keeps journal and reports `recovery-timeout`; retry heals |
| F11 | Temp/orphan files, non-atomic writes | Direct writes to final names, no orphan sweep | All new durable state uses write-temp → fsync → atomic rename → fsync-directory; leftovers collected by `quarantineTemps()` into `Quarantine/`, counted in report |
| F12 | Report cannot express discarded / needs-user-action | Counts + notices only | Additive fields `discarded`, `needsUserAction`, `skippedBusy`, `integrity`, `quarantinedFiles`; `isClean`; old initializer and fields unchanged |
| F13 | Kill at every write/recovery stage | No staged fault injection | 6 atomic-write crash stages + 14 recovery stages + 6 ledger stages, with real ephemeral files and fresh-instance restart assertions |
| F14 | Same-process concurrent engines | Actor per instance only | Same directory lock covers both processes and instances |
| F15 | Unicode / long data | Untested | 150 KB unicode round-trip, 4,000-repeat emoji/CJK ledger notes, 120-record concurrency test |

## Mechanisms added

- `RecoveryStoragePrimitives.swift` — `AtomicFileStore.write` (temp in same directory, file fsync, POSIX `rename` replacement, directory fsync), `read`, `quarantineTemps`, `quarantine(named:)`, FNV-1a checksum, `AtomicWriteStage` crash injection.
- `RecoveryLedger.swift` — versioned/checksummed framed records, one atomically written file per record, sequence + id, tolerant read with truncated/corrupt/version-mismatch census, quarantine, idempotent in-process replay, cached sequence (O(n) append).
- `RecoveryLock.swift` — directory lock with PID/heartbeat owner, stale detection with startup grace, evidence-preserving break, busy detection, release verification.
- `RecoveryEngine+Support.swift` — absolute sample-time rebasing, duplicate-row detection, watermark extraction, deterministic event ids, default roots.
- `RecoveryEngine.swift` — staged recovery with fault injection, cooperative deadline, ledger-backed watermarks, verified journal disposition, orphan sweep, truthful report. Public initializer extended with **defaulted** parameters only (old call sites unchanged).

## Tests added (aggressive, real ephemeral storage)

`FileBackedJournalStore` in `RecoveryTestSupport.swift` is a real FileHandle-backed journal (framed records in a temp directory, torn-tail tolerant). No storage logic is mocked; the only injected fault is a process-kill surrogate that throws at a named stage.

- `RecoveryAtomicFileTests` — 5 tests: all 6 atomic stages (old-or-new complete file, never partial), unicode/150 KB data, 16 concurrent writers, real filesystem failure, checksum sensitivity.
- `RecoveryLedgerTests` — 5 tests: round-trip, all 6 ledger stages, truncation/corruption/version skew + quarantine, idempotent replay, 120 concurrent unicode records.
- `RecoveryLockTests` — 5 tests: 12-way contention, dead PID, stale heartbeat, live owner, release/independence.
- `RecoveryCrashPointTests` — 6 tests: 14 recovery stages × crash+restart, crash after first committed row, disk-full + retry, repeated recovery, concurrent engines, deadline + retry.
- `RecoveryEdgeCaseTests` — 5 tests: missing audio, stale lock during recovery, unverified orphan kept, retention honored, damaged ledger quarantined.

Existing 11 tests were not modified. No test was weakened or deleted.

## Verification results

| Check | Command | Result | Evidence |
|---|---|---|---|
| Baseline (before changes) | `swift test --package-path Packages/L2-Engines/RecoveryEngine` | 11 tests, 0 failures | `logs/baseline-debug.log` |
| Debug suite (after) | `swift test --package-path Packages/L2-Engines/RecoveryEngine --jobs 2` | **37 tests, 0 failures** (26 new + 11 existing) | `logs/test-debug-07.log` |
| Release suite | `swift test --package-path Packages/L2-Engines/RecoveryEngine --configuration release --jobs 2` | **37 tests, 0 failures** | `logs/test-release-01.log` |
| Forbidden-pattern lint | `tools/lint-forbidden` | passed | `logs/lint-final.log` |
| Debug audit pass 2 (no code changes) | `swift test --package-path Packages/L2-Engines/RecoveryEngine --jobs 2` | **37 tests, 0 failures** | `logs/test-debug-final2.log` |
| Release audit pass 2 | `swift test --package-path Packages/L2-Engines/RecoveryEngine --configuration release --jobs 2` | **37 tests, 0 failures** | `logs/test-release-final2.log` |
| App release build (my run) | `swift build --package-path App/SuperflowApp --configuration release --jobs 1` under fence | **Build complete! (2.26 sec)** — green | `logs/app-release-build-final.log` |

Crash-point results: all 14 `RecoveryStage` cases (listSessions, acquireLock, readSegments, inspectJournal, createStream, replayStart, replayChunk, streamFinish, appendSegment, cleanSegment, finalize, recordFinalized, deleteJournal, sweepOrphans) passed crash-then-restart with: committed row intact, no duplicate rows, contiguous indices, recovered unicode text present, terminal `.recovered` status, journal disposed of exactly once and reported in `discarded`, clean ledger integrity, no leftover temp records. `appendSegment` crash-after-first-row also passed (dedupe on restart). Disk-full, bounded-time, concurrent-engine, repeated-recovery, missing-audio, stale-lock, orphan and damaged-ledger tests all passed.

## Exact app-wiring changes needed

No compile-time change is required: the original `RecoveryEngine(repository:journals:recognizer:clock:keepJournals:cleaner:)` initializer is preserved, and defaults place ledger state and locks in `Application Support/Superflow/Recovery/{State,Locks}` with a 180-second budget.

Recommended (optional) changes in `App/SuperflowApp/Sources/SuperflowAppCore`:
1. `AppEnvironment.makeRecoveryEngine(settings:)` — pass explicit roots/budget: `stateRoot: RecoverySupport.defaultRoot("State")`, `lockRoot: RecoverySupport.defaultRoot("Locks")`, `recoveryBudget: .seconds(180)`.
2. `AppCoordinator.recoverInterruptedSessions(environment:)` — surface the new truthful fields: distinct notices for `discarded` (journal removed only after verification), `needsUserAction` (list `reason` values; data retained), and `integrity.isClean == false` (damaged ledger records moved to `Quarantine/`).
3. No change needed in `Tests/Integration/Sources/FaultInjectionRecoveryTests.swift` — its `samplesReplayed`, row-count and retention assertions remain valid because default behavior was preserved.

## Honest UNVERIFIED items

- No literal `kill -9` of a real process was used. Crashes are precise in-process faults thrown after each real filesystem stage, followed by a fresh engine/store over the same on-disk bytes. This exercises the same persistent state a SIGKILL leaves, but is not a literal signal test.
- L1 `FileJournalStore` / `PCMJournalWriter` manifest and PCM formats were audited but not modified (outside ownership). Their torn-line/odd-byte handling remains as shipped; `Tests/Integration/Sources/FaultInjectionRecoveryTests.swift` covers that path and was not run by this agent.
- Ledger "applied" markers are in-memory per process. Cross-process idempotency relies on deterministic record ids plus repository segment-level dedupe, not a persisted applied set.
