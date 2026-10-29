# Microphone capture and DeepFilterNet 3

Required: working Fn dictation, raw durable journaling, DeepFilterNet 3 before existing Silero/ASR, default-on setting, required model download and genuine upstream logo on Models.

Evidence: macOS default input exists at 48 kHz, permission authorized, mute false. Existing mixer graph probe: 48,000 samples, all zero. HAL IOProc probe: 240,128 native samples, peak 0.833. Replace capture mechanism; do not change recognizer or gesture semantics.

1. Implement explicit Core Audio input capture, consumer-side conversion, route rebuilds and signal/stall diagnostics; test capture on hardware.
2. Pin verified Swift runtime, download checksum-pinned HF snapshot through app model flow, integrate length-preserving enhancer after raw journal and before recognition. Keep failure fallback and reset per recording.
3. Add default-on persisted setting and Models row using downloaded upstream logo.
4. Run affected tests, native inspection and app packaging; review owned diff, commit and push subject to repository Git rules.

Unverified claims: chosen model is FP16, not 2.2 MB INT8. Runtime depends on MLX for DSP setup. Supplied wrapper uses wrong compute enum and may append padding or lose tail; correct rather than copy those behaviors.
