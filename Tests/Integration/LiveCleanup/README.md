# Verify cleanup with the local model

The runner creates a temporary SwiftPM package outside the repository. It uses the repository's real llama.cpp adapter and cleanup engine without adding model dependencies to the default integration suite.

Set `SUPERFLOW_CLEANUP_MODEL` to a local S1-mini GGUF. Set `SUPERFLOW_CLEANUP_RESULTS` to a directory for the Markdown reports, then run:

```sh
Tests/Integration/LiveCleanup/run --filter LiveServiceTests.testLiveServicePreservesExamples
```

To include the synthetic 30, 60, and 120 minute cleanup soaks, set `SUPERFLOW_CLEANUP_SOAK=1` and run:

```sh
Tests/Integration/LiveCleanup/run
```

The runner uses a release build with two compilation jobs. Inference uses GPU placement and two contexts sharing one model. The service uses its default chunk and retry settings.

The soak generates exactly 150 words per simulated minute, waits for the complete result, and compares every normalized output token with the input. Reports include actual model requests, generated tokens, errors, capped calls, and fallback chunks. Timing excludes model load, prewarm, and input generation. It includes chunk planning, inference, retries, stitching, and validation. Cleanup RTF is cleanup seconds divided by simulated audio seconds.

These soaks exercise already-transcribed text. They do not measure ASR, recording, streaming stop-to-final latency, or quality on the owner's dictations. One run per length cannot select a worker count or establish a performance improvement.
