# Plan: headphone-safe capture, clearer VAD input, accuracy audit

## Root cause (verified locally)
Built-in mic is Float32/48 kHz, so `HALInputStream` works. It accepts *only* Float32
device formats and reads raw bytes as floats. AirPods/headsets commonly expose
integer PCM, which is either rejected at start or read as near-zero float garbage —
the reported silent, crackly input. Enhancement runs only when enabled, so there is
no device-adaptive cleanup or loudness on the recognition path.

## Stage 1 — dynamic headphone-safe capture
- `InputDevice.swift`: expose a format-support query; keep default-device preference.
- `HALInputStream.swift`: accept linear PCM Float32/Float64/Int16/Int24(in 32-bit)/Int32;
  convert to mono Float32 inside the IOProc using preallocated scratch (no alloc/lock/log),
  then reuse the existing sample-rate converter.
- `MicrophoneCapture.swift`: rebuild on format/route change (already present); keep
  raw journal untouched.
- Headless tests: synthetic PCM conversion correctness, clipping, non-finite handling.

## Stage 2 — crisper, fuller pre-ASR / VAD input
- New `VoiceClarity` DSP in `AudioEnhancement` (Lumen-inspired, causal): 70 Hz high-pass,
  mild 300 Hz mud cut, 3 kHz presence lift, soft compressor, peak ceiling.
- Wire after denoise and before `AudioLeveler` in `SessionEngine+AudioPath`.
- Headless tests: finite, bounded, sample-count preserving, gain/limit behavior.
- Build, focused tests, `make buildfix`, reopen the app.

## Stage 3 — accuracy engine
Audit real pipeline order, add ambiguity/negation/number/self-correction regressions,
narrow harmful dictionary behavior, add bounded context vocabulary. Headless tests only;
do not fabricate acoustic or human-rating results.
