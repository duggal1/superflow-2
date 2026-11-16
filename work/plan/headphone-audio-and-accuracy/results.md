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

## Aggressive headless accuracy probes (second pass)

Enabled only by env vars; run with `swift test --package-path ... --filter <name>`.

1. `HeadlessAccuracyProbeTests.headlessASRAccuracyProbe` synthesizes 10 read-aloud
   technical sentences with macOS `say`, converts to 16 kHz mono, runs the real
   Nemotron 3.5 ASR and writes raw commits. Result: clean speech is recognized almost
   perfectly. `time to first token`, `tokens per second`, `intermittent`, `evaluate
   Metal GPU utilization and model accuracy`, `ensure`, `why`, `Kubernetes`,
   `OpenTelemetry`, `CI/CD` all survive. Only `Redis cache invalidation` →
   `rediscache and validation` and `OAuth` → `Off` were acoustic errors.
2. `HeadlessStageAttributionTests` ran those exact raw strings through every
   deterministic stage. No stage invented `intermediate`, `Insured`, `More accuracy`,
   `while` or `Jeration`. `Numbers` correctly formats `five hundred three` → `503`.
3. `headlessBoundaryPauseProbe` inserted 900 ms silence at phrase and mid-word
   boundaries. Phrase pauses produce 3 ASR segments; a mid-word pause turns
   `token` into `two` / `Can`. Feed cadence 512 vs 5,120 samples gives identical
   results, so the 600 ms RMS endpoint — not feed chunk size — is the boundary
   failure mode. This confirms the segmentation diagnosis and refutes the
   cleanup-model theory for those errors.
4. `HeadlessS1ProbeTests` ran the real pinned S1-mini via `LlamaCppRuntime` headlessly.
   It preserved all reported words; it did rewrite spoken `five hundred three` to
   `530`. `HeadlessGuardProbeTests` proves production `CleanGuard.verify` rejects
   that mutation (it also conservatively rejects benign `two point zero` → `2.0`,
   so deterministic Numbers owns numeric formatting).
5. One real deterministic defect found and fixed: `rediscache` matched the spaced
   trigger `redis cache` and collapsed to `Redis`, dropping `cache`. `LexiconStage`
   now rejects only compressed-token matches where the canonical is a prefix of the
   trigger and drops an entire trailing word; phonetic repairs still work.

Final `make verify` passes every suite except the pre-existing stale
`StreamingProfileTests.selectableSpeechModelsHaveNativeIncrementalOutputPaths`
assertion from commit 61f5c7e (retired models), which was deliberately not touched.

## S1-mini rejection investigation (third pass)
Plan: `work/plan/s1-guard-split/plan.md`.

Headless chain with the real installed Q4_K_M model and its direct llama.cpp runtime:
- S1-mini itself produces correct grammar, self-corrections, bullets, numbered lists
  and email layout. Cleanup was being rejected *after* the model ran.
- Both of the user's long transcripts ended in `STATE: fallback` before the fix.
  Reject reasons, in order, were `protectedLost` (literal numeric formatting),
  `timeout("cleanup")` (fixed 1.5 s deadline on a ~150-token input), and
  `contentChanged` from `MeaningCarriers` (apostrophe/casing changes, a single-letter
  `P 95` -> `P95`, and strict lemma churn limits on long text). A standalone replica
  of every check isolated the final failure to the `P` casing rule.
- Fixes, all general (no sentence-specific rules): numeric data compared as whole
  digit runs (so `200ms` -> `200 ms` passes but `500` -> `1500` fails); paths/dotted
  identifiers still exact; contraction spellings normalized before negation counts;
  casing compared case-insensitively and single-letter tokens ignored; revision cues
  (`no sorry/wait/actually`) relax lemma limits; interactive deadline scales with
  input tokens (12 ms per token above 60, capped by the 30 s background ceiling).
- No retry loop exists in `CleanupService`; one model call per chunk, fallback only.
- Final headless result: both transcripts finish `STATE: cleaned` with S1's bullets
  and grammar intact. Remaining wrong terms (`redish cash`, `APOINT`, `open trace`,
  `KV cash`, `skeptical decoding`, `withoutput`) are ASR acoustic errors upstream of
  S1-mini; they are not fixed by guard changes and are not claimed as fixed.
## Brutal headless battery (final)
- Added `testBrutalInvariants`: ten general cases (negation, 503/403/500/200,
  paths, URLs, weekday revision, numeric self-correction, apostrophe negation,
  bullets, 55-step long dictation) asserting only facts that must survive.
- It found two more real fallbacks: `actually no Wednesday` counted as a negation,
  and `three thirty` -> `3:30` flagged as a missing tail. Fixed generally in
  `MeaningCarriers` (revision cues, calendar and trailing-number words) and
  `TruncationDetector` (spoken-number tail equivalence). All ten cases pass.
- Full probe battery re-run green: ASR accuracy, boundary pauses, S1 grammar/lists,
  stage attribution, and end-to-end transcripts. `make verify` green except the
  pre-existing stale `StreamingProfileTests` assertion.

- Pre-ASR audio raised: leveler target -20 -> -15 dBFS, baseline gain 1.5 -> 2.0,
  enhancer output gain 1.5 -> 2.0, presence +1.5 -> +3 dB, mud cut -1.2 -> -2 dB,
  high-pass 70 -> 80 Hz. Tests updated to the new measured targets.
