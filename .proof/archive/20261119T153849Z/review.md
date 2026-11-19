# Independent review — 7-agent extreme-quality task

Fresh-context reviewer posture: I did not build this. A green test suite is not
evidence when the assertions do not gate the reported quality. Anything partial,
unverified, smoke-only, weaker than a sibling, or outside the request is FAIL.
`UNVERIFIED` is never `PASS`. Reviewed against `.proof/requirements.md` (10
requirements) and the specialist reports; reviewed snapshot is `main @ 738d810`
plus the uncommitted `.proof/quality/audit/*` files.

## Execution constraints (transparency)

- Acquired `/tmp/superflow-build-lock` with `mkdir` before every build/test,
  released with `rmdir` after; one process at a time; `--jobs 1`; each command
  wrapped in `timeout 300`. Load stayed 1.9–3.4 (well under the 25 stop line).
- Two pre-existing stale `swift-test` processes (PIDs 58169, 92257) were already
  hung for 30+ min on the `EnhancementDeepFilterNet` `.build` flock before I
  started; the parent's background `make verify` (PID 84369) was deadlocked
  behind them. I did not start and did not kill them. My target packages had no
  held locks, so my checks ran cleanly. These are flagged, not silently ignored.
- I did not run the full 17-package two-pass audit (per instruction) and did not
  commit, push, spawn sub-agents, or edit anything except this file.

## Spot-checks I re-ran myself (headless, current tree)

| Check | Command | Result |
|---|---|---|
| Forbidden lint | `tools/lint-forbidden` | `Forbidden-pattern lint passed.` rc=0 (3 s) |
| Number regression | `swift test --package-path Packages/L2-Engines/TextNumbers --filter SpokenHundredsRegressionTests --jobs 1` | **2 tests, 0 failures**, rc=0 |
| Medical / academic / gaming corpus | `swift test --package-path Packages/L2-Engines/TextPipeline --filter 'testDomainMedicalDictation\|testDomainAcademic\|testDomainGaming' --jobs 1` | **3 tests, 0 failures**, rc=0 |
| Fresh executed-corpus re-run | `SUPERFLOW_CORPUS_EXECUTE=1 swift test ... --filter testExecutedSubsetScores --jobs 1` | rc=0, 20 records written — but **core facts OK 14/20, grammar 8/20**; the test PASSES while recording failures |
| App release build | `swift build --package-path App/SuperflowApp --configuration release --jobs 1` | **TIMEOUT rc=124** at 300 s on three separate attempts (last progress 1071/1278 tasks, mid third-party MLX Metal C++ compile, no Swift error). UNVERIFIED by my own fresh run. Prior agents report green builds (island-bright 87 s, knowledge-front 135 s, performance 155 s), so this is an environment/cold-cache limit of the fenced 300 s cap, not proof of broken code. |

## Requirement verdicts

| # | Requirement | Grade | One-line evidence |
|---|---|---|---|
| 1 | 7 sub-agents, disjoint ownership, design docs + no-smoke rules | **FAIL** | No ownership manifest and no per-agent branches for this task; only self-authored `.proof/progress.md:8,22` lines claim 3 read-only + 6 agents (not 7); what instructions/docs were given to agents is unprovable from the tree — unverified process claim. |
| 2 | 200 broken samples, 50/140–150/larger tiers, diverse domains, real S1-mini or honest NOT-EXERCISED | **FAIL** | `report.json` totals `executed 20 / notExercised 180` (90% never run); only short(50w)/long(140–150w) tiers, no "larger" tier; `AggressiveCorpusShortTests.swift:3080` gates execution behind `SUPERFLOW_CORPUS_EXECUTE=1` (default skip) and records verdicts to JSON without asserting them — green test, no quality gate. |
| 3 | Fix fact corruption (numbers, coordinates, clock times, final punctuation), not weaken tests | **FAIL** | Fresh re-run of the real Tier-0 path still corrupts numbers: `A1-S-0051` "37°C" → "30 you know 7°C" and `A1-L-0041` required 12000/10200 missing; `agent1-report.md:107-113` lists these as unfixed; final punctuation is fixed (format 20/20 fresh) but the named number-corruption defect persists in a documented pipeline path. |
| 4 | Island brighter blue, pixel-grid sharp, 60 FPS, measured frame numbers, two screenshot passes | **FAIL** | Two 53-PNG passes and pixel deltas (+7–42%) + frame probe (60.0 fps synthetic clock, 0.65 µs/frame) exist (`.proof/island-bright/report.md:41-58`), but `report.md:75-77` marks live on-screen FPS UNVERIFIED — offscreen `NSHostingView` disables `TimelineView` animation, so the actual running UI's 60 FPS was never observed. Central runtime claim unverified. |
| 5 | Delete/rebuild knowledge landing page; fix history line clamping / vertical breaking / overflow | **FAIL** | Source fixes and green focused tests exist (`knowledge-front/report.md:42-65, 82-92`), but `report.md:109-124` states **no rendered screenshots**, partial text selection, and a shared `DiffTranscript` mismatch — the visual result was never looked at; UI change without a headless screenshot fails. |
| 6 | Real SQLite knowledge backend (CRUD, search, import/export, learning), aggressive DB tests, front/back handshake | **PASS** | `.proof/knowledge-back/report.md:32-74`: real FTS5 + triggers/migration v6, 24-way concurrent-write test, real-DB restart/idempotency tests, StorageSQLite 51/51 + FeatureDictionary 18/18 + FeatureShortcuts 16/16 green; `provided-backend-api.md`/`expected-backend-api.md` handshake confirms additive, source-compatible API. |
| 7 | S1-mini reliability/speed (no silent fallbacks, thunder-fast M1), loudness, real VAD, port HEX ideas | **FAIL** | Real improvements measured (`.proof/performance/report.md:56-80, 93-120`: 1.7–2.7× faster, no truncation, VAD RMS 0.003→0.182, HEX ports attributed), but `report.md:64,165` admits 1-min audio still times out at the shipped 1,500 ms deadline, and WER, ANE, 10-min latency and chunked-vs-single-shot model equivalence are all UNVERIFIED — partial. |
| 8 | Crash recovery: atomic writes, checksummed journal, idempotent replay, crash-point tests | **PASS** | `.proof/recovery/report.md:18-68`: atomic temp→fsync→rename→fsync, `SFRL` framed FNV-1a ledger, 14 recovery stages × crash+restart, 37/37 tests green in debug and release; `RecoveryAtomicFileTests`/`RecoveryCrashPointTests` use real ephemeral files. Literal `kill -9` caveat is a stronger surrogate than the requested crash-point tests. |
| 9 | Never freeze the Mac: one process, build fence, GPU/CPU throttle, 5-min caps, honest load monitoring | **PASS** | Every report documents `/tmp/superflow-build-lock` + single process + `--jobs 1` + 300 s caps + load logs (peak ~22 in `performance/report.md:150-154`); my own 5 checks followed the fence, released it, load 1.9–3.4. Stale-process leak noted in flags but it did not load the machine. |
| 10 | Completion audit: two clean passes, zero FAIL/UNVERIFIED, independent review, then commit and push | **FAIL** | `pass1.txt`/`pass2.txt` show 0 failing test runs but the audit checks exit codes only, not requirement-level UNVERIFIED (reqs 2/3/4/5/7 carry open UNVERIFIED items); the audit artifacts themselves are uncommitted (`pass1.txt` modified, `pass2.txt`/`summary.txt` untracked); and this independent review returns FAILs, so "zero FAIL" cannot stand. |

**Grade: 3 PASS / 7 FAIL.** Not done: reqs 1, 2, 3, 4, 5, 7, 10.

## Auto-flags (items to justify)

- **Changed frozen test:** `Packages/L1-Adapters/AudioCpp/Tests/StreamingProfileTests.swift` (commit 9cf481e) removed two expected model IDs with a comment citing retirement in 61f5c7e. Verified `qwen3ASR17B`/`voxtralRealtime` are `status: .unavailable` + `retiredProfiles` (`ModelProfiles+Streaming.swift:4,13,31`), so justified — but it is still a test-expectation change.
- **Weakened / non-gating test:** `AggressiveCorpusShortTests.swift` `testExecutedSubsetScores` records 5-dimension verdicts to JSON but asserts only `!out.isEmpty` and count==20; it passes with 14/20 core-fact and 12/20 grammar failures. The "green corpus suite" is not a quality gate.
- **Strengthened (not weakened) test:** `RecoveryLockTests.swift` (9cf481e) added a 12-way arrival gate to remove a flake; coverage increased.
- **New dependencies:** none in this task's scope — `git diff 51ebf0f..HEAD -- '**/Package.swift'` is empty. Earlier local packages (`ClearlyInput`, `ClearlyStealth`, `FeatureIntelligence`) predate this task; no third-party dep added.
- **Files changed outside scope:** cleanup commit d2dd68f deleted `PLAN.md`, three `fonts/*.woff2`, `click-soft.mp3`, `.proof/quality/island-pixel-final/*.png` and `tools/validate-headless/window-share-dump` — not requested by the 10 requirements.
- **Environment flag:** two stale `swift-test` processes and the parent's deadlocked `make verify` were present at review start (not mine, not killed); the `/tmp/superflow-build-lock` fence was released after each of my commands.
