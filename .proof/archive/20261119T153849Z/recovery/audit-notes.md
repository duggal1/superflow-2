# Recovery audit — evidence (baseline, before changes)

Source read in full: `Packages/L2-Engines/RecoveryEngine/{Package.swift,Sources/SuperflowRecoveryEngine/RecoveryEngine.swift,Sources/SuperflowRecoveryEngine/RecoveryReport.swift,Tests/RecoveryEngineTests/RecoveryTests.swift,Tests/RecoveryEngineTests/RecoveryStorageFailureTests.swift}`.
Supporting contracts read: `Ports/{Storage,Audio,Recognition,System}.swift`, `TestKit/{InMemoryRepository,TimeAndAudio,FakeRecognition}.swift`, `AudioJournal/{FileJournalStore,PCMJournalWriter}.swift`, `Kernel/{Models,Deadline,Settings}.swift`, `Tests/Integration/Sources/FaultInjectionRecoveryTests.swift`, `App/.../AppEnvironment.swift`, `App/.../AppCoordinator.swift`, `tools/lint-forbidden`.

## Baseline test result
`swift test --package-path Packages/L2-Engines/RecoveryEngine` (debug): 11 tests, 0 failures (9 RecoveryTests + 2 RecoveryStorageFailureTests). Log: `logs/baseline-debug.log`.

## Failure modes (line numbers refer to original RecoveryEngine.swift / RecoveryReport.swift / adapters)

| # | Failure mode | Evidence | Consequence before change |
|---|---|---|---|
| F1 | Crash after some `appendSegment` calls but before `finalizeSession` | RecoveryEngine.swift:91-99, 135 | `nextIndex` from max+1 avoids duplicate indices, but ASR is re-fed from a millisecond-truncated position; recovered segment timestamps are relative to the replay start (0), so re-runs drift/overlap. No record of exactly which samples were committed. |
| F2 | Crash between `finalizeSession` and `journals.delete` | RecoveryEngine.swift:135-143 | Session becomes `.recovered`, so `unfinishedSessions()` no longer returns it; journal directory is orphaned forever. No report of the discarded/orphaned data. |
| F3 | Partial/truncated journal manifest or PCM | PCMJournalWriter.swift:34,185-193; FileJournalStore.swift:14-29,92-115 | Corrupt JSONL lines are silently skipped; missing `.pcm` files are silently skipped; odd-byte PCM tails are rounded down. Samples can vanish with no notice. |
| F4 | No checksums / no version on journal records | FileJournalStore.swift:5-9 (plain `Codable` JSONL), no magic/version/CRC | Bit rot or a torn write that still decodes as JSON yields wrong sample positions; old/new format skew is undetectable. |
| F5 | No inter-process lock | Whole file (no lock primitive) | Two simultaneously launched apps can replay the same journal and append duplicate transcript rows. |
| F6 | Stale lock (if one existed) not detectable/broken | n/a | Would permanently block recovery after `kill -9` of the owner. |
| F7 | Disk-full mid-write | RecoveryEngine.swift:95,119,136 catches, but `journals.freeBytes()` never consulted; `appendSegment` failure caught by the outer `catch` at :100 which leaves already-appended segments | Partial writes; retry replays from a derived position; no truthful "needs user action" signal. |
| F8 | ASR failure / missing recognizer model | RecoveryEngine.swift:69,85-89 | Journal retained (good) but report only has a free-text notice; no structured action. |
| F9 | Missing audio/transcript files | FileJournalStore.swift:95 (`fileExists` skip), RecoveryEngine.swift:59-61 (`total == 0` continue) | A session can be finalized `.recovered` with zero segments and zero samples, silently losing the session's audio. |
| F10 | Unbounded recovery time | No deadline/deadline check in loop | A hung recognizer or a huge journal blocks launch indefinitely. |
| F11 | Temp/orphan files | PCMJournalWriter writes directly to final `.pcm` names; no temp+fsync+rename; no orphan sweep | A crash during segment creation can leave a zero-length final file that the manifest references, so replay silently drops that lane. |
| F12 | Truthfulness of report | RecoveryReport.swift:27-50 has counts + notices only | `discarded`, `needs-user-action`, `quarantined`, integrity counts are unrepresentable; `hasRecoveredText` is the only structured success signal. |
| F13 | Process kill at each stage | No staged fault injection in code or tests | No evidence that crash+restart preserves state at every stage. |
| F14 | Concurrency within one process | `RecoveryEngine` is an actor, but two instances are independent | No mutual exclusion across instances. |
| F15 | Unicode/long data | No tests | JSONL/JSON payload corner cases (surrogates, 100k+ chars) untested. |
