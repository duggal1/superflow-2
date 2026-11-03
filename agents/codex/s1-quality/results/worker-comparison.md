# S1-mini concurrent-request probe

Release SwiftPM build, installed S1-mini Q4_K_M, GPU, one shared model with four prewarmed llama.cpp contexts. Each batch made four identical short synthetic requests. Five rounds used alternating concurrency orders (1/2/4 then 4/2/1); setup and model load were excluded. No live ASR or XPC was active in the measured path. Other machine processes were running; load average around 5 on 8 logical CPUs. The test checked every output against a greedy baseline, rejected capped responses, and counted request errors.

| Concurrent requests | Median batch seconds | Range seconds | Requests | Mismatches, caps, or errors |
|---|---:|---:|---:|---:|
| 1 | 1.541 | 1.483–1.620 | 20 | 0 |
| 2 | 1.386 | 1.359–1.452 | 20 | 0 |
| 4 | 1.392 | 1.386–1.408 | 20 | 0 |

Four contexts with four concurrent requests produced no measurable improvement over two in this test. This does not establish the performance of independently configured two- versus four-context helper processes, long dictation, contention with ASR, end-to-end insertion, cold startup, RAM pressure, or model output quality on real speech. The primary bottleneck was not profiled, so the 1-vs-2 difference is not a general speedup claim. Current live cleanup is configured to use two workers and the XPC helper defaults to two contexts in the working tree; that application path was not benchmarked here.

Command: `SUPERFLOW_CLEANUP_MODEL=<installed GGUF> swift test --package-path Packages/L1-Adapters/LLMLlamaCpp --configuration release --jobs 2 --filter ParallelCapacityProbeTests`. Full results are printed by the test; no transcript or audio from a user was used.
