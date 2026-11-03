# audio.cpp runtime replacement

Cause: app composition and model setup depend directly on FluidAudio for ASR, VAD, and diarization.

1. Clone audio.cpp and prove its Metal build supports Nemotron streaming ASR and diarization.
2. Add a focused L1 adapter using the upstream C ABI with serialized handle ownership.
3. Replace composition, model installation/catalog settings, packaging and CLI callers; remove FluidAudio packages.
4. Preserve durable audio, explicit download boundaries, cancellation, final flushing and meeting speaker labels.
5. Verify narrow adapter tests, native streaming with Metal, then app compilation and dependency checks.

Acceptance: no FluidAudio runtime dependency; streaming ASR by default; explicit Metal selection; working final transcripts and meeting diarization.
Do not delete the working runtime before the replacement builds and passes its streaming smoke test.
Upstream pin: 06c13737cc39481787a03465697b58b1c954b56f.
