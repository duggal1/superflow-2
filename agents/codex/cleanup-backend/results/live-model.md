# Live cleanup verification

Model: s1-mini-q4_k_m.gguf, 484219808 bytes. GPU placement, two shared-model contexts.

Command: set SUPERFLOW_CLEANUP_MODEL to the local GGUF and SUPERFLOW_CLEANUP_REPORT to this file, then run `swift test --package-path Packages/L1-Adapters/LLMLlamaCpp --jobs 2 --filter LiveCleanupTests`.

Load and prewarm: 1.182436542 seconds. This is one functional run, not a benchmark.

## Use case 1

Input:

okay so I need you to open the file hero.tsx in the components folder then go to lib backend folder and fix the prospect main engine the path should be lib/backend/main/engine/router/prospect-main-engine.ts and change the status code from 500 to 429 when the rate limit is hit also update the constant MAX_RETRY_COUNT from 3 to 5

Output:

Okay, so I need you to open the file hero.tsx in the components folder, then go to lib/backend folder, and fix the prospect main engine. The path should be lib/backend/main/engine/router/prospect-main-engine.ts, and change the status code from 500 to 429 when the rate limit is hit. Also, update the constant MAX_RETRY_COUNT from 3 to 5.

Prompt tokens: 154. Generated tokens: 84. Latency: 1137 ms. Hit token cap: false.

Protected tokens are checked as complete tokens, with exact case and original order. This test does not assert zero content damage for unprotected prose. In particular, compare `lib backend folder` in the input with the output before accepting it in the full pipeline.

## Use case 3 with discourse fillers

Input:

I was thinking about the performance and you know like it keeps saying warming the GPU or warming the CPU and that is really bad

Output:

I was thinking about the performance, and it keeps saying warming the GPU or warming the CPU, and that is really bad.

Prompt tokens: 103. Generated tokens: 25. Latency: 425 ms. Hit token cap: false.

## Cancellation

Cancellation requested 20 ms after starting a long example. CancellationError returned: true. Time from cancel to return: 0.360285875 seconds.

Checks occur between generated tokens and prefill batches. One observation does not establish a worst-case bound.

Not measured: Spike B safe-length sweep, Spike C tokenizer error, Spike D session throughput/RSS/p95, Spike E equivalence, the owner's 100-dictation golden set, or real-model 30/60/120-minute soaks.
