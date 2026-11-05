# Superflow dictation reliability and latency: investigation and execution

Date: 2026-11-05. Base: main at aa24595. Scope: dictation UI, streaming recognition, S1-mini scheduling.
Do not touch unrelated ASR models, microphone capture formats, or `main` directly.

## Reproduced in source

1. `IslandWings.swift` still renders `LiveLine` during listening and hands-free when the legacy setting is true. The earlier success reducer fix affects only the final state, not recording.
2. `SessionEngine+Recognition.persist` synchronously asks the cleanup/XPC tokenizer for a token count, then awaits a cleanup coordinator whose bounded queue can suspend submission. The recognition event reader cannot progress during these waits.
3. `LlamaCppRuntime.completion` starts the deadline after acquiring a worker from `WorkerPool`, so a request can queue for seconds before its latency budget begins.
4. `SessionCleanupCoordinator.finish()` previously waited for all pending cleanup without a stop-time budget.
5. Existing success snapshot test expected `.landed` despite the revised reducer returning `.idle`.
6. Current full CI failed on an upstream sherpa-onnx binary archive HTTP 504 during SwiftPM resolution. This is external; not evidence that code tests passed or failed.

## Architecture and implementation

Recording: Core Audio -> journal -> optional enhancement -> native streaming audio.cpp.
On a committed ASR segment: save raw text durably, then schedule cleanup without any XPC tokenizer or queue-space wait. The cleanup queue holds up to 128 metadata requests. If saturated, preserve and mark the original text as fallback rather than blocking audio recognition or silently discarding words. Process interactive work first, bounded to the two existing S1-mini contexts.

At stop: allow the coordinator a short, explicit final cleanup drain (default 2500 ms) then return raw text for unfinished segments. Cancel worker tasks; guard against late writes after the paste has happened. Keep no retry on the S1-mini helper. This is an end-to-end stop budget, not a promise that all speech is normalized when the CPU/GPU is overloaded.

For the Island: microphone and meter state remain visible during recording. Never render raw, partial, or finalized dictation text in the Island during normal recording, even if an older setting enabled it. A paste failure alone raises a transcript card. User-initiated History remains accessible separately. Meeting live text is unchanged.

Inside llama.cpp: calculate one request deadline before attempting worker acquisition, expire pool waiters at that deadline, and pass the same instant into generation. Cancel timeout tasks and resume each queued continuation exactly once.

Metrics (no transcript or audio content): `session.asr.slow_feed.ms`, `session.audio.enhancement.ms`, `session.stop.cleanup_wait.ms`, `session.cleanup.queue_full`, `session.cleanup.finish_deadline`, existing `cleanup.chunk.*` phase timing.

## Verification gates

- Model queue: timed-out waiter releases its queue slot and cannot acquire a released context later.
- ASR ingestion: injected token counter is never invoked by committed recognition; 140 persisted segments submit without waiting for slow S1-mini.
- Stop tail: long-running cleanup stops waiting within the explicit bound, raw text remains available, and a canceled worker cannot overwrite it.
- Island: successful insertion returns to idle; a legacy live-text setting cannot show words while listening, hands-free, or processing. Failed insertion still offers finalized text to copy.
- Native macOS: run focused Swift tests for SessionEngine, FeatureIsland, WorkerPool and LlamaCleaner, then `make verify` when dependencies are reachable.
- On an actual M1, collect at least 100 short dictations and a representative 30/60-minute recording, recording p50/p95 stop-to-paste, ASR feed stalls, S1 prefill/generation, queue waits, fallback frequency, and correctness. No claim of 90–100 tokens/s, zero spikes, or fully fixed hardware performance without those measurements.

## Constraints and tradeoffs

The official S1-mini GGUF Q4_K_M file is about 462 MiB. Disk size is not an in-memory footprint or measured generation throughput. S1-mini remains enabled and uses its pinned prompt and thinking-disabled template. Its ~1,000-token recommended input length still justifies the existing 850-token hard cap; neither large inputs nor more workers guarantee higher throughput. Preemption favors delivering recognized speech over unbounded editing waits. Do not remove raw transcription, replace the model, or start speculative extra inference attempts.
