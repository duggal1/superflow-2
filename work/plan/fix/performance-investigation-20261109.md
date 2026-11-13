# Plan: Dynamic parallel S1-mini chunking (supersedes 2-worker revert)

## Direction (owner)
Undo the 2-worker revert. S1-mini (~1,000-token budget) must be spawned multiple
times via dynamic chunking: pack each chunk near the budget, run chunks in parallel.
Goal: extremely fast transcription cleanup by default.

## Root cause of slow cleanup
Files: ChunkPlanner (soft target 250), CleanupService, LlamaCppRuntime.
- ChunkPlanner packs chunks to ~250 tokens → 8 small calls for a 10-min transcript;
  each pays full prefill + system-prompt overhead. The 850 hard cap is mostly unused.
- Fixed worker counts (2) under-use the 6 parallel S1 lanes the runtime can serve.

## Fix
- Restore 6 everywhere: Settings default 6 + v3→v4 migration; LlamaCppRuntime
  sessions 6; SessionCleanupCoordinator, ChunkPlanner, CleanupService clamps 6.
- Dynamic chunking: softTokenTarget default 250→800 (slack under the 850 hard cap
  and the model card's ~1,000-token guidance). A 2,000-token transcript becomes
  ~3 chunks instead of ~8; all run in parallel across 6 workers.
- Keep lazy launch (no S1 at app open) so "laggy on open" stays fixed. Keep n_ctx
  3072. No ChunkPlanner logic change (it already cuts at sentence boundaries).

## Tests
- ChunkConcurrencyTests: rewrite for 800-token chunks / 6-lane fan-out (one test
  big enough to prove the 6 clamp from workers 8).
- LongInputBudgetTests: re-check long-transcript ordering under new target.
- Run TextCleanup, LLMLlamaCpp, SessionEngine, Kernel, FeatureSettings,
  InferenceHelper suites. Run ParallelCapacityProbe with the real GGUF for
  concurrency medians (aggressive perf evidence).
- Rebuild app, launch, confirm no helper at open; first-dictation path unchanged.

## Verify + ship
- make lint; commit with explicit paths; push to main. Update issue.md entries.
