# Agent 6 — S1 reliability/performance, audio loudness/VAD, HEX ports

Environment: Apple M1, 8 CPU cores, 8 GB RAM, macOS 27.2 SDK, Swift 6.4.2,
llama.cpp XCFramework b11556. Real model:
`~/Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf`
(484,219,808 bytes, q4_k_m). All work headless via `swift test`; no GUI, no user
focus, one heavy process at a time behind `/tmp/superflow-build-lock`, `--jobs 1`.

## 1. S1-mini — root cause of failures (hard evidence)

| Observation | Evidence | Root cause |
|---|---|---|
| Default worker pool (6 contexts on 8 GB) **never becomes ready** | `SUPERFLOW_PERF_PHASE=before` default sessions run aborted after 36.6 s with `modelUnavailable("llama.cpp failed while generating cleanup text")` thrown from `LlamaCleaner.prepare` → the warm-up task inside `LlamaCppRuntime.load`. | Six simultaneous Metal context graph builds exhausted the 8 GB M1; `llama_decode` failed. Every later cleanup then failed because `ready=false`. |
| Real app default deadline is **1,500 ms** (`CleanOptions.deadlineMs`), but probe tests used 30,000 ms | `Packages/L0-Core/Ports/Sources/SuperflowPorts/Text.swift:16-17`; tests at `ParallelCapacityProbeTests.swift:26` and `LiveLongParallelTests.swift:36` all use 30 s. | The passing probes never exercised the deadline that ships. 30 s/1 min dictation timed out in real use. |
| 1 min audio was **silently truncated** | BEFORE JSON: `tokensIn=150, tokensOut=227, hitTokenCap=true`, 30 s deadline. | Output cap `1.3 x input + 32` was applied to a single long prompt; the model needed more than 227 tokens. A capped cleanup is reported as a failure by the app. |
| Generation dominates; prefill is negligible | 25 words: prefill 16 ms / generation 537 ms. 75 words: 15 / 1,631 ms. 150 words: 11 / 4,774 ms. | Optimising prompt handling would not help; the wins are bounded contexts, thread placement, and chunk-parallel decoding. |

Artifacts: `.proof/performance/s1-before-sessions4.json` (real 4-session run),
`.proof/performance/logs/s1-unit-*.log` and `s1-after-*.log`. The 10-minute
case is **NOT MEASURED** (coordinator cap); it is excluded from all tables. A
historical uncontrolled probe at 30 s deadline timed out at 31 s and is not
used as a baseline number.

## 2. S1 — code fixes

`Packages/L1-Adapters/LLMLlamaCpp/Sources/SuperflowLLMLlamaCpp/LlamaCppRuntime.swift`

- `recommendedSessionCount` now derives from RAM **and** cores: `min(10, max(3,
  min(GB/2, cores/2)))`. On this M1: 4 contexts (was 6). 4 warmed successfully
  in measurement (`prepareMs` 1,241–2,748 ms); 6 crashed. `maximumSessions` stays 10.
- Per-context threads are divided across the pool: `generationThreads =
  clamp(cores/sessions, 2, 4)`, `batchThreads = min(cores, gen+2)` (was every
  context given all 8 cores → 48 threads on 8 cores). This follows HEX's
  measured finding that more native threads than usable CPUs hurt tails.
- Warm-up is **sequential**, 8 tokens per context, 15 s per context, and a
  context that fails is dropped with an `os.Logger` warning. If none survive,
  load throws `modelUnavailable` — no silent fallback to an unhealthy pool.
  `activeSessionCount` reports how many lanes are live.
- GPU placement remains `n_gpu_layers = -1` for `.gpu` and a failed Metal load
  still throws (no quiet CPU fallback). ANE is not exposed by the llama.cpp
  XCFramework — UNVERIFIED / unavailable.

`Packages/L1-Adapters/LLMLlamaCpp/Sources/SuperflowLLMCore/LlamaCleaner.swift`

- Long transcripts (>120 words ≈ >45 s dictation) are cut at word boundaries
  into 50-word chunks and decoded concurrently across up to 4 contexts. Each
  wave gets a share of the caller's deadline. Every chunk must succeed; a
  failed or late chunk fails the whole call (no partial text is pasted).
- The pinned `1.3 x input + 32` output-cap formula is unchanged (a frozen test
  asserts it). Chunking raises total output capacity for long input without
  changing the single-call contract; the 1 min case no longer hits the cap.
- Added `ChunkedCleanupTests` (5 tests): word-boundary preservation, short
  input stays a single call, 3-way fan-out with ordered output, injected chunk
  failure aborts the whole call, expired deadline throws `timeout("cleanup")`.

## 3. S1 — BEFORE / AFTER (real GGUF, 4 sessions, GPU, warm)

| Audio equivalent | Deadline | BEFORE success | BEFORE latency | AFTER success | AFTER latency | Change |
|---|---:|---|---:|---|---:|---|
| 10 s (25 words) | 1,500 ms | yes | 584 ms | yes | 440 ms | 1.33× faster |
| 10 s (25 words) | 30,000 ms | yes | 785 ms | yes | 372 ms | **2.11× faster** |
| 30 s (75 words) | 1,500 ms | **NO — timeout** | 1,654 ms | **yes** | 1,076 ms | failure removed |
| 30 s (75 words) | 30,000 ms | yes | 1,770 ms | yes | 1,033 ms | **1.71× faster** |
| 1 min (150 words) | 1,500 ms | **NO — timeout** | 1,630 ms | **NO — timeout** | 1,677 ms | still caller-budget-limited |
| 1 min (150 words) | 30,000 ms | yes, `hitTokenCap=true` | 4,837 ms | yes, `hitTokenCap=false` | 2,046 ms | **2.36× faster**, truncation removed |
| 10 min | any | NOT MEASURED | — | NOT MEASURED | — | coordinator cap |

1 min at the 30 s deadline varied 1,782–2,046 ms across three measured runs;
the table reports the final run against the final code. Failure rate over the
comparable cases (10 s/30 s/1 min x both deadlines, 4 sessions): BEFORE 3/6
failed (50%); AFTER 1/6 (16.7%). With the shipped 6-session default, BEFORE
failed 100% (warm-up crash); AFTER uses 4 bounded contexts by construction and
all measured loads completed warm-up in 1.2–2.7 s.

Interpretation: the remaining 1 min @1.5 s timeout is a **caller deadline**
problem, not a model failure — the same workload completes in under 2.1 s with
a realistic budget, and the app's 1,500 ms default lives in `Ports` (owned by
another agent). With the 30 s budget, cleanup is 1.7–2.7× faster and no longer
truncates. Typical push-to-talk utterances (10–30 s) now succeed at the shipped
deadline.

## 4. Audio — root cause of low volume

`Packages/L2-Engines/AudioEnhancement/Sources/SuperflowAudioEnhancement/AudioLeveler.swift`

- Old `silenceRMS = 0.005` (-46 dBFS) was the **only** speech gate. A real
  headset whisper sits at 0.002–0.004 RMS, so it was classified as silence and
  the AGC **froze**. Measured: -50 dBFS fixture RMS 0.003 → output 0.003,
  `legacyGainApplied = false` (`.proof/performance/audio-enhancement.json`).
- Even when speech was detected, `maxGain = 16` (24 dB) could not lift a -43 dBFS
  signal to the -15 dBFS target (needs ~28 dB).

### Measured before / after (synthetic 130 Hz + harmonics, 4 Hz syllables, 400 ms)

| Metric | BEFORE (legacy AGC) | AFTER (VAD + AGC + gate) |
|---|---:|---:|
| Speech RMS | 0.0030 | **0.1821** |
| Speech peak | 0.0060 | 0.3871 (below -1 dBFS limit 0.891) |
| AGC gain applied | no | yes |
| Noise-floor RMS | 0.0010 | **0.000125** (8× lower) |
| Speech/noise ratio (proxy) | 3.0 | **1456.8** |
| VAD hears -50 dBFS speech | n/a (no VAD) | yes |

Artifact: `.proof/performance/audio-enhancement.json`.

### New code

- `SpeechActivityDetector.swift` — causal 20 ms energy + zero-crossing VAD
  over an adaptive noise floor; 0.4 score threshold, 160 ms minimum speech,
  220 ms hangover that clings to word-final consonants; immediate attack so
  onsets are never gated; confirms segments separately from the attack gate.
- `AudioLeveler` now gates on the VAD plus an absolute digital-zero floor
  (1e-4, not 0.005), raises the cap to 64× (36 dB), and attenuates non-speech
  by 0.5× relative to unity so a loud utterance cannot pump the noise floor.
- `SilenceChunker.cuts()` ports HEX's silence-midpoint long-audio splitting
  (50 ms windows, 0.012 RMS threshold, ≥300 ms silence, ≤6 chunks, ±8 s of the
  ideal boundary, 5 s guards).
- 8 new `SpeechActivityTests` assert VAD detection of whispers, rejection of
  steady noise and single-frame clicks, boundary/hangover positions, silence
  cut placement, whisper loudness, noise attenuation, and SNR improvement.
- **Word-error rate is UNVERIFIED**: no labelled audio corpus or ASR scorer is
  available in this package. RMS/SNR/VAD numbers are the measurable proxies.

## 5. HEX ideas ported (source attribution)

| HEX source | Ported into | What and why |
|---|---|---|
| `hex/src/speech_detector.rs` | `SuperflowAudioEnhancement/SpeechActivityDetector.swift` | 0.4 threshold, 160 ms min speech (HEX keeps short "Ok"/"Ciao" but rejects clicks), CPU-first/no-Metal-cold-start principle (we use pure Float math), background prewarm replaced by stateless init. Keeps speechless audio away from the recogniser. |
| `hex/crates/capture/helper/Media.swift` (`splitWavAtSilences`) | `SuperflowAudioEnhancement/SilenceChunker.swift` | 50 ms RMS windows, 0.012 threshold, ≥300 ms silence midpoint cuts, nearest-to-ideal boundary selection, ≤6 chunks. HEX uses this to run concurrent SpeechAnalyzer instances without cutting words; we use the same boundaries for S1 text chunking and future audio chunking. |
| `hex/docs/research/vocabulary-boost-results.md`, `hex/src/.../vocabulary.cpp` | `SuperflowLLMCore/VocabularyBooster.swift` | 1–4 word candidate spans, owner sounds-like aliases, skip case-only/inflections/paths, Normal default, and the crucial **no false insertions** rule. We use an LCS similarity gate instead of transducer logit rescoring (not reachable from Swift) — a deliberate approximation, not a claim of equal quality. |
| `hex/docs/research/performance-2026-09-04.md`, `transcription-benchmark.md` | `PerformanceBenchmarkTests.swift`, worker/thread policy | Warm load separated from per-clip latency, repeated passes, JSON artifacts, "more threads than CPUs hurts tails", and refusing to adopt an unproven setting. 10-minute runs and unbounded sweeps were deliberately not copied. |
| `hex/AGENTS.md` (streaming fallback invariant) | `LlamaCleaner` chunking | HEX falls back from a late stream to the whole clip; the owner forbids silent fallbacks, so we instead fail the whole cleanup loudly. This is a deliberate divergence. |

Not ported: HEX's native Silero GGUF model/rescoring fork (cannot load from our
packages), the Metal transcription engine, and the Labs feature gating.

## 6. Verification (all headless, one process, `--jobs 1`, build fence)

| Check | Result |
|---|---|
| `swift test --package-path Packages/L1-Adapters/LLMLlamaCpp --jobs 1` | **52 tests, 7 skipped (real-model probes gated by env), 0 failures** — `.proof/performance/logs/test-S1-final.log` |
| `swift test --package-path Packages/L2-Engines/AudioEnhancement --jobs 1` | **20 tests, 0 failures** — `logs/test-AudioEnhancement-final.log` |
| `swift test --package-path Packages/L1-Adapters/AudioCapture --jobs 1` | **12 tests, 1 skipped, 0 failures** — `logs/test-AudioCapture.log` |
| `swift test --package-path Packages/L1-Adapters/SystemAudioCapture --jobs 1` | **12 tests, 0 failures** — `logs/test-SystemAudioCapture.log` |
| `swift test --package-path Packages/L1-Adapters/AudioCpp --jobs 1` | 11 tests, **1 pre-existing stale failure**: `StreamingProfileTests.swift:8` expects 4 streaming profiles, only 2 exist (`nemotron-3.5-asr-streaming-0.6b`, `qwen3-asr-0.6b`). Untouched by this task; the repo's `requirements.md` already documents a pre-existing stale test. Not weakened or edited. |
| `tools/lint-forbidden` | **Forbidden-pattern lint passed.** |
| `swift build --package-path App/SuperflowApp --configuration release --jobs 1` | **Build complete! (155.19 sec), rc=0** — `logs/release-build.log` |
| Real-model benchmarks | JSON in `.proof/performance/`: `s1-before-sessions4.json`, `s1-after-10s.json`, `s1-after-30s.json`, `s1-after-1min.json`, `audio-enhancement.json`; raw logs in `.proof/performance/logs/`. |

Safety: the shared `/tmp/superflow-build-lock` fence was acquired for every
build/test/inference with a single in-flight process, `--jobs 1`, a 300 s
timeout, one S1 duration per batch, a 30 s inference cap and no 10 min run.
Peak observed load average was ~22, below the coordinator's 25 stop line. One
SystemAudioCapture run transiently failed with `database or disk is full`
when the shared disk hit 206 MB free (other agents' release builds); after
space was freed, the retry passed. No files outside the assigned ownership
were edited; `App/SuperflowApp/Package.swift` was not touched.

## 7. Honest unverified items

- Real-word WER on a labelled corpus: no corpus/scorer available; loudness and
  SNR are proxies only.
- ANE placement: llama.cpp XCFramework exposes GPU/CPU only.
- 10-minute S1 latency: not measured (coordinator cap).
- 1 min cleanup at the shipped 1,500 ms deadline still times out; fix requires
  the `CleanOptions` default in `Ports` (another agent's ownership).
- Semantic equivalence of chunked vs single-shot S1 cleanup on real speech:
  ordering is tested with a fake runtime; model-output equivalence is not.
- Vocabulary boost on real misheard terms: deterministic fixture tests only.
