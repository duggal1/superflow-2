# Long-dictation release latency — proof

## What changed

`LiveDictationCleanup` now compacts confirmed sentence checkpoints into a single
reusable prefix instead of retaining every checkpoint in a 48-piece buffer.
On a long dictation that buffer filled up, after which no further cleanup was
offered until ASR committed a segment; the remaining text was left for
stop-time cleanup. Completed prefixes are merged and released as soon as they
are confirmed, so offering continues for the whole session.

Safety is unchanged: a prefix is reused only when the final recognizer text
matches the exact raw words. A correction at the live tail withholds its
preceding sentence for stop-time cleanup. A non-cleaned result disables reuse
for the pending prefix and keeps the raw text.

## Measurements (ms unless stated)

### Stop-to-insertion, real Nemotron + S1-mini, one context (previously committed path)

| Audio | Legacy | Cleanup during capture |
| --- | ---: | ---: |
| 10 s at 1x | 901–1,005 | 587–644, zero unfinished |
| 30 s at 2x | 1,806 | 1,253–1,268, zero unfinished |
| 60 s at 2x | 2,641 | 3,598 and 19,177, unfinished cleanup |

Measured from engine stop through an in-memory insertion sink; physical
keyboard and target-app paste are outside the measurement. Repeated runs are
in `.proof/archive/20261121T075824Z/stream/`.

### 30-minute speech-equivalent coverage (this change)

- Cache replay: 450 sentences / 4,500 words offered one at a time. The cache
  accepted the full transcript, kept 4,490 words as a reusable prefix and left
  the final sentence for stop-time cleanup. Assertions cover exact word count,
  order and text. Wall time 0.491 s (unit test).
- Real S1-mini cleanup of the same 4,500-word payload, one context, two runs:
  `LIVE_S1_LONG input_words=4500 output_words=4500 elapsed_ms=209838
  output_ids=450 token_cap=false` and `elapsed_ms=187981` with the same output
  checks. 188–210 s across runs; all 450 item numbers survived in order and no
  output cap was hit. This shows why cleanup must overlap capture: ~200 s of
  model work cannot be deferred to a sub-second release.

### Integrity and failure modes

- Correction at the live tail keeps its preceding sentence for final cleanup — PASS.
- Fallback result disables reuse for the whole pending prefix; raw text retained — PASS.
- Revised final text rejects a stale prefix by exact match — PASS.
- Checkpoint lookahead and exact punctuation preserved — PASS.
- Bounded queues: offering limited to 4 in-flight pieces and one retained
  checkpoint; the SessionCleanupCoordinator pending cap (128) is unchanged.

### Resources

- One S1 inference context only (`activeSessionCount == 1`) on the 8 GB Mac.
- Earlier archived two-context run timed out; the four-context run was stopped
  when macOS reported 15% free memory. No parallel-context path was shipped.
- Peak process RSS measured earlier: 0.93 GiB.
- No 30-minute audio replay: no such fixture exists, and a disk-heavy run was
  unsafe at 2.0 GiB free. The 30-minute figure is a speech-equivalent
  (4,500-word) cleanup proof, not a microphone-to-paste benchmark.

## Test evidence

- `swift test --package-path Packages/L2-Engines/SessionEngine --scratch-path
  .proof/build/SessionEngine --jobs 2` — 53 tests, 0 failures on both passes,
  including the five `LiveDictationCleanupTests` cases.
- `swift test --package-path Packages/L1-Adapters/LLMLlamaCpp --scratch-path
  .proof/build/LLMLlamaCpp` — 54 tests, 8 opt-in skipped, 0 failures.
- `SUPERFLOW_CLEANUP_MODEL=<installed s1-mini GGUF> swift test --package-path
  Packages/L1-Adapters/LLMLlamaCpp --scratch-path .proof/build/LLMLlamaCpp
  --filter LiveSingleContextLongTranscriptTests` — 1 test, 0 failures on both
  passes (212.067 s and 188.0 s wall).
- `git diff --check` — clean.
