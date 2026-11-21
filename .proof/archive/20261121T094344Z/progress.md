# Plan

Goal: lower release latency for long dictations and produce repeatable end-to-end proof on the real ASR + S1-mini path, up to a 30-minute speech-equivalent replay.

Non-goals: no new UI, no model replacement, no tuning that weakens transcript integrity, no killing unrelated background work, and no more than one S1 inference context on this 8 GB machine unless a bounded run proves it safe.

Invariants: native ASR remains the authority; every source word is either accepted cleaned output or recoverable raw fallback; chunk seams preserve ordering and context; queues stay bounded; final insertion is once-only; model requests stay within the configured 800-token cap; no disk-heavy build/replay while free storage is low.

Failure modes: stale partial replaces a correction; a chunk times out or is rejected; inference queue backs up during real-time speech; session stop races a pending cleanup; replay output is incomplete; RAM pressure/swap growth or disk pressure invalidates measurements.

Plan:
1. Inspect shipped streaming cleanup, replay fixture/driver, tests, machine pressure, and current git state. Verify: `git status --short --branch`, focused source/test reads, `df -h .`, `vm_stat`, `uptime`.
2. Establish the actual long-session limiter and add acceptance coverage before code. Verify: run focused tests against current code and capture baseline replay outputs/timings.
3. Implement the smallest safe throughput improvement for long sessions. Verify: focused tests and build; exercise retries, corrections, ordering, caps, and queue bounds.
4. Run repeated real-pipeline replays at short, medium, long, and 30-minute equivalent sizes; confirm final content and count fallbacks. Verify: replay harness logs and resource counters; no run if available storage or memory is unsafe.
5. Re-run all affected suites and audit all five requirements. Commit, check status, pull, push `main`. Verify: clean git status and remote head contains the commit.

Progress:
- Read `rules.yaml`, `git.yaml`, and the prior proof notes. Previous artifacts are being preserved under `.proof/archive/` per the new-task rule.
- Current machine has 8 GB RAM, 3.9 GiB available disk, and high load from unrelated processes; no unrelated process will be stopped.
- Found the long-session limiter: the 48-piece checkpoint buffer stopped offering new cleanup work on long dictations. Added a 4,500-word regression test first; it failed against the old cache.
- Implemented completed-prefix compaction with exact-match validation, correction-boundary protection and fallback disablement. All five focused cache tests pass.
- Live single-context S1-mini cleanup of the 4,500-word payload passed: 209,838 ms, 4,500 words, 450/450 IDs, no token cap.
- Full SessionEngine suite passed (53 tests, 0 failures). LLMLlamaCpp live long test built and passed. Results in `.proof/results.md`.
- Removed stale path-bound build caches from the archive to keep free disk above 3 GiB. No unrelated process was stopped; no subagents used.
