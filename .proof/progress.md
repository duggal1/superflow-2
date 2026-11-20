# Progress — clean sweep (2026-11-18)

## Plan
- [x] Read rules.yaml + git.yaml (binding). Full mode; multi-agent git mode.
- [x] Inspect git state: main @ 51ebf0f, origin/main in sync, 30 modified + 170 untracked files.
- [x] Secret scan of all files to be staged: clean (only false positive: design `Tokens.swift`).
- [x] Snapshot uncommitted work to /private/var/folders/ct/cwpf7vpn059fkp932tq9zm4m0000gn/T/opencode/superflow-uncommitted.diff for stable review.
- [x] Launch 3 read-only sub-agents: history analyst (ses_e103e6752ffdaHjHW316IyEftq), test runner (ses_e103e6751ffeYdQZRo8skRRVYI), diff reviewer (ses_e103e674bffeEIq8BpbDwQwOqB).
- [x] Archive stale .proof state to .proof/archive/20261118T174334Z/; write fresh requirements.md + progress.md.
- [ ] Collect sub-agent reports.
- [ ] Resolve any BLOCKERs found by reviewer / test failures.
- [ ] Create agent/clean-sweep branch, stage all work, commit (6-12 words), merge main, push branch.
- [ ] Open PR agent/clean-sweep -> main and merge with merge commit; confirm origin/main advanced.
- [ ] Return to main, verify clean tree (`git status --porcelain` empty).
- [ ] Completion audit: two consecutive full verification passes.

## Log
- 2026-11-18T17:43Z did/investigated: git state, gitignore, Makefile, recent timestamps, secret scan, proof archive / result: clean secrets, main in sync, 3 subagents launched / next: collect reports.
- 2026-11-18T17:48Z did/history-agent report: all last-90-min work uncommitted; newest LineFormatter safety net broke 2 frozen tests / result: fixed production rule `wordCount(formatted) > 3` (no test edits); focused TextLineFormat run 19 tests / 0 failures / next: full suite result, diff review.
- 2026-11-18T18:12Z did/diff review + full suite / result: SAFE TO COMMIT ALL; 593 tests passed, 1 pre-existing AudioCpp stale-test failure on main / next: commit.
- 2026-11-18T18:10Z did/committed 205 files on agent/clean-sweep, PR #16 merged to main @ 8b8b26c, tree clean except later full-audit.sh artifact / result: baseline pushed / next: collect 6 specialist agent reports.
- 2026-11-18T18:15Z did/spawned 6 subagents: footprint, speed, S1-mini quality, Intelligence page, reliability, cleanup(worktree) / result: running / next: reports, fix the stale AudioCpp test, final commit + push.


## Brutal S1-mini testing (2026-11-21, cw-7778, no sub-agents)
- did: read mandatory instructions, registered cw, located S1-mini in green-apps.
  result: model installed (462 MiB), llama-server available, only 10 GiB free -> no full App build.
  next: lightweight headless driver around the installed model.
- did: tools/brutal-s1/brutal_s1.py — opt-in, loopback, pinned prompt, 21 brutal cases, latency + streaming TTFT.
  result: raw S1-mini 11/21; p50 ~298 ms, p95 ~499 ms, TTFT p50 ~23 ms, no caps/errors.
  next: classify false assertions vs real defects.
- did: corrected false assertions, added 3 more list cases.
  result: honest raw baseline 11/21; real defects: glued-hyphen, comma, pseudo-decimal and Bullet lists.
  next: check which survive the real downstream pipeline.
- did: BrutalFormattingProbeTests with measured raw S1 outputs through real post-model stages.
  result: final period, ordinal date, S1-mini name, card list already repaired; 4 bullet defects survive.
  next: implement conservative layout-only repair.
- did: SpokenMarkerListShaper + EnumerationDetector separator hints; wired into shapeOutput.
  result: all 4 defects now render as `- item` bullets; shaper/detector tests green.
  next: full TextPipeline suite, final raw probe, commit/push.
