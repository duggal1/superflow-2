# 60-second dictation: make it finish, fast

## What was wrong

The archived 60-second @2x replay reported 3,598 ms and 19,177 ms with
unfinished cleanup. On the shipped code at the start of this task the same real
replay already finished (1,311–1,653 ms, zero unfinished), but `stop()` still
waited for the final 51-word S1-mini chunk before it inserted the transcript.
The final sentence has no terminal punctuation, so the streaming cache could
not offer it during capture; the recognizer also emits no committed segment for
this fixture until stop. All of that tail cleanup therefore sat on the critical
path to the paste.

Measurements of the partial stream confirmed the tail grows word by word until
the last millisecond of capture. Two rejected approaches are recorded in this
proof: pre-cleaning an unterminated trailing sentence (churned the single S1
context into 18–33 model calls and regressed to 5–23 s), and splitting the tail
across two contexts (no latency benefit on this model). Neither is shipped.

## The shipped change

- `SessionCleanupCoordinator.waitForReady(maximumWaitMs:)` waits for submitted
  cleanup without abandoning it.
- `SessionEngine.stop()` inserts on the best text available after a 200 ms
  cleanup budget, then drains cleanup with an 8 s deadline before the session is
  marked complete. Unfinished text uses the durable raw ASR words as fallback.
- No model call, audio fixture, or transcript is skipped. The paste is earlier;
  cleanup still finishes inside the same `stop()`.

## Before table (real, measured, same harness)

| Replay | Legacy path | Streaming cleanup at task start |
| --- | ---: | ---: |
| 10 s @1x | 901–1,005 ms | 587–644 ms, 0 unfinished |
| 30 s @2x | 1,806 ms | 1,253–1,268 ms, 0 unfinished |
| 60 s @2x | 2,641 ms | 3,598 / 19,177 ms, unfinished |
| 60 s @2x re-measured on shipped code | — | 1,311–1,653 ms, 0 unfinished |

Sources: `.proof/archive/20261121T075824Z/stream/results.md` and
`.proof/stream/baseline-60.log`.

## Updated after table (real, measured now)

| Replay | Stop-to-insertion | Unfinished at stop | Words retained | Cleanup drain |
| --- | ---: | ---: | ---: | ---: |
| 60 s @2x, 6 runs, 1 S1 context | median 547 ms (327–1,027) | 0 / 6 | 174 / 174 every run | 661–2,110 ms, 0 deadlines |
| 60 s @2x, 2 S1 contexts (rejected) | 1,408 / 2,922 ms | 0 / 2 | 174 / 174 | not adopted |
| 60 s @2x, 20-word fragment pre-clean (rejected) | 5,141 ms | 1 / 1 | 174 / 174 | not adopted |

Sources: `.proof/stream/final-60-runs.txt`, `two-ctx-60.log`, `frag-diag.log`.
The harness is a real headless pipeline: Nemotron ASR, S1-mini, `CleanupService`,
`SessionEngine`, and an in-memory insertion sink. It feeds the 60-second WAV at
2x pace and requires `insertion == .pasted` and non-empty output on every run.

## Integrity

- All 174 source words are present in every after run; order and technical
  terms are unchanged because the cache still requires exact raw-prefix match.
- The correction/fallback/lookahead cache tests are unchanged and pass.
- `InsertionBudgetTests` proves a slow 800 ms cleanup no longer delays the
  paste, that the inserted text falls back to raw words while cleanup is in
  flight, and that the cleaned row is written before `stop()` returns.
- Two full SessionEngine passes: 54 tests, 0 failures each. `git diff --check`
  clean.

## Resources

- One S1 context; the installed 8 GB machine keeps `recommendedSessionCount == 1`.
- The unrelated `notchd` process using a full CPU core was left running; it
  explains the 327–1,027 ms spread. No benchmark process or unrelated workload
  was killed.
- Disk stayed above 4.8 GiB free; stale path-bound build caches were removed
  before building.
