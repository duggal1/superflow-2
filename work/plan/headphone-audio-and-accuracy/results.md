# Verified results — headphone audio and accuracy pass

## Production pipeline (actual code, not docs)
`TextPipelineBuilder.make` order: selfCorrection → preCleanupRepair → aiEraPreCleanup →
preCleanupModelNames → techDictionaryPreCleanup → disfluency → [S1-mini cleanup] →
postCleanupRepair → aiEraPostCleanup → dedupe → format → commands → shortcuts → spokenCode →
codingLanguage → numbers → lexicon → codeAware → lineformat → normalize → modelNames → techDictionary.
Audio: HAL device format → SPSC ring → AVAudioConverter to 16 kHz → raw journal →
DeepFilterNet → VoiceClarity → AudioLeveler → journal archive → streaming ASR.

## Root causes verified
- AirPods/headsets commonly report integer PCM; `HALInputStream` previously accepted only
  Float32 and read raw bytes as floats, producing near-silent crackly capture. Local probe:
  built-in mic is Float32/48 kHz, which is why only external devices failed.
- No pre-ASR tonal/level chain existed; enhancement was all-or-nothing with the user toggle.
- `vocab_v4.json` contained ordinary-language aliases: "next year", "next year's",
  "next years", "nexts year(s)", "next year js" → Next.js and "open eye" → OpenAI (Tier A).
  The gate promoted the next-year family in any recognized developer app.
- Explicit self-corrections were never repaired: "Thursday actually no Wednesday" kept Thursday.

## Changes
- `PCMDecoder` + `HALInputStream`: Float32/64, Int16, Int24 (packed and in 32-bit), Int32,
  big/little endian, interleaved first-channel, all converted in the IO callback into
  preallocated scratch; no allocation, locks, logging or concurrency in the callback.
- `VoiceClarity` (Lumen-inspired): causal 70 Hz high-pass, 300 Hz mud cut, 3 kHz presence,
  gentle compressor; inserted after denoise and before the existing true-peak leveler.
- Removed 8 harmful aliases from the runtime catalog; added an ordinary-language deny in
  `TechDictionaryGate` that survives catalog regressions but respects explicit user pins.
- `SelfCorrectionStage`: narrowly removes an abandoned weekday/month only when an explicit
  revision cue follows ("actually no", "actually", "I mean", "no,").

## Verification actually run
- AudioCapture tests 12 (1 pre-existing skip) pass; new PCM decoder cases cover all encodings.
- AudioEnhancement tests 12 pass; VoiceClarity cases cover finiteness, sample count, rumble
  rejection, bounded gain and reset.
- SessionEngine enhancement integration passes after replacing an unrealistic DC fixture with
  a speech-like tone; raw journal remains byte-identical and the toggle still bypasses DSP.
- TextPipeline 84 tests pass; new regressions failed before the catalog/gate and
  self-correction fixes and pass after.
- `make lint`, `make buildfix`, `make run`: app rebuilt, signed and opened.

## Limits / not verified
- No AirPods were connected during verification; hardware capture remains UNVERIFIED.
- ASR contextual biasing is not exposed by the installed native recognizer; no acoustic
  biasing was invented. Context selection remains catalog-gating only.
- No recorded speech corpus, human ratings, 200-utterance evaluation, WER/latency/memory
  measurements or real-model S1-mini comparison were available. Acoustic and 9/10 quality
  claims are UNVERIFIED.
- Dynamic 10–50-entry per-session vocabulary and Technical/Professional profile switching
  are not implemented; the bundled catalog still contains 2,212 aliases.
