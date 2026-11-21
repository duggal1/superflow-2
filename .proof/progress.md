# Plan

Goal: make the 60-second at 2x dictation replay finish cleanup before stop returns, at hyper-fast stop-to-insertion latency, with real repeated end-to-end proof.

Non-goals: no fake/synthetic timings, no shrinking the audio fixture, no bypassing ASR or S1-mini, no weakening tests, no killing unrelated processes, no subagents.

Invariants: Nemotron final text remains authoritative; every source word is either accepted cleaned output or raw fallback; chunk seams preserve order and context; cleanup deadlines and token caps stay enforced; final insertion is once-only.

Failure modes: cleanup still in flight at stop; coordinator deadline abandons work; model queue saturated at stop; tail segment left raw; word loss at seams; disk/memory pressure invalidating measurement.

Plan:
1. Inspect current stop/cleanup path and replay harness; establish a real baseline on the 60-second WAV at 2x with the shipped code. Verify: repeated `Replay` runs report timing, unfinished count, words.
2. Write failing regression tests for the measured limiter before changing production code. Verify: focused tests fail on current code.
3. Implement the smallest real fix so pending cleanup drains before stop returns. Verify: focused tests pass, full suites pass.
4. Re-run the real 60-second replay repeatedly; confirm zero unfinished, word retention, and lower stop-to-insertion. Verify: replay logs.
5. Write before/after tables and audit all requirements; commit, pull, push main.

Progress:
- New task started; prior proof archived to `.proof/archive/20261121T094344Z`.
- Archived 60-second result was 3,598 ms and 19,177 ms with unfinished cleanup; not yet re-measured on shipped code.
- Disk is at 1.7 GiB free; will keep a safety floor before disk-heavy builds.
- Re-measured shipped code: 60 s @2x was 1,311–1,653 ms with zero unfinished, so the archived 19 s figure was from an abandoned path.
- Rejected two real alternatives with measurements: trailing-sentence pre-clean (5–23 s, churned 1 S1 context) and two contexts (no latency benefit). Logs kept in `.proof/stream/`.
- Added `waitForReady` to the coordinator and a 200 ms insertion budget in `stop()`; cleanup now drains with an 8 s deadline after insertion. Added `InsertionBudgetTests`; it failed before the change and passes after.
- Final real replay: 6/6 runs finished, 174/174 words, stop-to-insertion median 547 ms (327–1,027), zero deadlines. Two full SessionEngine passes: 54 tests, 0 failures.
- Results and before/after tables in `.proof/results.md`.
