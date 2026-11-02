# Short cleanup latency and requested concurrency
Evidence: requests up to 600 tokens remain one chunk, and LlamaCleaner recounts completed output even when generated-token metadata exists.
- TextCleanup: aim for 250-token sentence-aware chunks, retain 600-token protected-span hard cap and bounded worker pool; reuse measured per-chunk token counts and avoid linear tokenizer round trips for token-heavy input.
- LLMLlamaCpp: skip redundant output tokenization when generated-token metadata is present; keep fallback for runtimes without it.
- Tests: reproduce 250/500-token chunking and worker overlap; verify metadata and unknown-count paths; run affected package tests and lint.
- Do not change prompt, model, GPU placement, default cleanup, output safety, or insertion behavior.
- Real 5–10-second stop-to-visible-paste root cause and before/after performance remain unmeasured; use packaged diagnostics and owner recordings, not simulated timings, for claims.
