# S1-mini verification on Apple M1

Two consecutive headless trials accepted real S1-mini output on all 32 warm cases. The corpus included 29 short inputs, a 210-word medium input, an 840-word long input, and the streaming audio replay transcript. Every expected batch ID and protected literal survived the long runs. The cold probe retained the input and reported `model not ready` before the model was loaded.

| Measurement | Trial 1 | Trial 2 |
| --- | ---: | ---: |
| Short median | 352 ms | 398 ms |
| Short p95 | 488 ms | 544 ms |
| Medium cleanup | 3.27 s | 3.67 s |
| Long cleanup | 14.25 s | 16.48 s |
| 30-second replay transcript cleanup | 1.31 s | 1.56 s |
| Cached model preparation | 0.65 s | 0.60 s |
| Peak process RSS | 0.93 GiB | 0.93 GiB |

- The installed GGUF SHA-256 matched the manifest's pinned Superwhisper model. The inference helper's live model test also passed.
- The initial corpus had six warm rejections. Before the dedupe fix, the long run timed out at 120 seconds. Sampling located repeated protected-range rescans in the inner comparison loop. The longer identity-cleaner tests also exercise bounded overlap assembly.
- Two contexts timed out on the long workload and took about 32 seconds. The four-context run was stopped when macOS reported 15% system-wide free memory. The one-context default is specific to machines with 8 GB RAM or less.
- Real Nemotron streaming processed 30 seconds in 4.13 seconds across 96 chunks after startup. Its final text reached S1-mini in the replay. This measures native streaming throughput and cleanup separately. It does not measure packaged-app microphone-to-paste latency or WER.
- The existing ASR fixture has no transcript reference labels. The synthetic cases check the expected corrections and content retention by directly comparing the application output. These results do not establish quality for arbitrary speech.

Verification passed for 116 TextCleanup tests, 32 focused TextPipeline tests, 46 enabled llama.cpp tests, the live inference-helper test, and lint. Seven opt-in llama.cpp tests were skipped by the package suite. The broad TextPipeline test-target compile hit the 120-second limit, so the focused run compiled the five relevant test files against the current source.
