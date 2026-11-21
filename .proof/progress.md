Use the real, cached Q4_K_M weights via the native cleaner and production text pipeline. Keep build and runtime sequential. Assess ASR separately with local WAV replay. Interpret dash bullets as Markdown lines beginning with "- ". Keep the existing safety fallback for actual inference failures. Use strict semantic and formatting assertions, replay after each fix, run focused suites and lint, and record failures and timing distributions.

- Native S1-mini baseline recorded six warm rejections across 25 cases, plus grammar and term casing defects. Streaming Nemotron replay processed 30 seconds in 4.13 seconds after model load.
- Sampled the stalled long test and removed per-comparison protected-range rescans in dedupe. The same long corpus moved from a 120-second test timeout to tens of seconds.
- Tested two Metal contexts and observed a long-input deadline; stopped the four-context probe as system free-memory estimate reached 15%. Single context is the default at 8 GB RAM.
- Added regression coverage for Markdown preservation, explicit corrections, agreement, and repeated text around chunk seams. The proofs use synthetic text and a local existing WAV fixture.
- Two consecutive final live trials passed all 32 cases each with zero warm fallbacks. Short p95 was 488–544 ms. The 840-word cleanup took 14.25–16.48 seconds. The provider hash matched the model manifest.
- TextCleanup passed all 116 tests. LLMLlamaCpp ran 53 tests with zero failures and seven opt-in tests skipped. The native helper's live-model test and lint passed.
- The seven-chunk concurrency test now explicitly uses its intended 800-token target. Production stays at 600 and all original assertions are preserved.
- The focused pipeline run passed all 32 tests. Stage-order tests assert the explicit pre-model layout and numbers stages and the enabled optional grammar stage. The broad test target exceeded the build timeout, so the run used an isolated manifest with the relevant test sources.
