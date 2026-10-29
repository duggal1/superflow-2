# Live synthetic cleanup soaks

One release-build run per length on real S1-mini Q4_K_M, GPU, two contexts, default CleanupConfig. Inputs represent speech at 150 words/minute and contain six-word sentences with sequential change numbers. The timer includes planning, model calls, retries, stitching, and final validation. It excludes model loading, prewarm, input generation, ASR, and recording. These are cleanup completion times for already-transcribed text, not streaming stop-to-final measurements.

| Simulated minutes | Input words | Seconds to final | Cleanup RTF | Requests | Successful calls | Errors | Capped calls | Prompt tokens | Generated tokens | Final fallback chunks | Exact content |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 30 | 4500 | 103.043 | 0.057246 | 10 | 10 | 0 | 0 | 8973 | 8193 | 0 | true |
| 60 | 9000 | 281.153 | 0.078098 | 32 | 32 | 0 | 6 | 22126 | 20777 | 2 | true |
| 120 | 18000 | 683.285 | 0.094901 | 88 | 88 | 0 | 23 | 53037 | 50024 | 7 | true |

No throughput comparison, safe-length calibration, session-count choice, or p95 claim follows from one run per length. The real-model calls and consumed output token counts above confirm inference happened inside each timed region. Fallbacks and capped calls remain visible because rejecting output can be faster than successful cleanup.
