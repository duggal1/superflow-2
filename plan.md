# SuperFlow

## Native macOS Dictation & Meeting Transcription — Master Build Plan

- Platform: macOS 15+, Apple Silicon (M1 and newer)
- Language: Swift 6 (6.4.1+ version), strict concurrency
- Execution: fully local; no cloud transcription, cleanup, or telemetry
- ASR: FluidAudio only, genuine streaming only
- Primary model: NVIDIA Nemotron 3.5 ASR Streaming 0.6B, contingent on a validated FluidAudio/Core ML build
- Text cleanup: deterministic Swift → S1-mini through llama.cpp → gated Harper
- Storage: SQLite with crash-recoverable audio journals
- Authority: this plan defines implementation; `DESIGN.md` defines appearance and Island geometry

Read this entire plan and `DESIGN.md` before changing code. Preserve implemented features, interfaces, and tests unless a measured incompatibility requires an ADR.

## 0. Rules for the Coding Agent

- Follow the current repository and `DESIGN.md`; do not redesign UI or replace working modules casually.
- Inspect the installed package source, declarations, release tags, model cards, and licenses before using third-party APIs. Do not invent signatures or assume an old tutorial is current. The attached DeepFilterNet and cleanup code drafts are uncompiled references, not approved production code.
- Ship native Swift. Permitted native bridges: `llama.cpp` and a minimal Rust/C ABI for Harper. No Python service, Electron, or network inference.
- One responsibility per module, strict dependency boundaries, constructor injection, and tests outside production source folders. Write an ADR before changing an architectural boundary.
- Complete Phase 0 verification before locking a model, compute backend, latency promise, or enhancement algorithm.
- Run `make verify` after each phase: release build, tests, dependency check, lint, formatting, and forbidden-pattern checks. Warnings are failures.
- Never log, upload, or include user audio/transcripts in diagnostics. Network use is restricted to explicitly approved model downloads and optional update checks.
- Preserve speech and text through fallbacks. A failed enhancement, VAD, ASR, cleaner, grammar gate, or paste must not silently erase captured content.
- Prefer measured simpler solutions to stacked models, speculative optimization, or additional background passes.

## 1. Product Contract

Build a private, responsive, reliable alternative to Wispr Flow / Superwhisper with these v1 features:

- System-wide push-to-talk and hands-free dictation with live partials and one final insertion.
- Streaming ASR with an adaptive noise-resistant microphone front-end.
- Deterministic cleanup of disfluencies, numbers, currency, code tokens, dictionaries, and shortcuts.
- S1-mini language cleanup, protected-token validation, and optional high-precision Harper grammar corrections.
- Native Island control, main window, dashboard, contribution graph, searchable history, settings, and onboarding.
- Meeting capture of microphone plus system audio, speaker labels, timestamps, and Markdown/JSON export.
- Persisted raw transcripts, bounded streaming memory, journal replay, and recoverable partial failures for 1–10-hour sessions.

### Non-goals for v1

- Cloud AI, summaries, mobile, Intel Macs, App Store distribution, automatic language switching in the UI, progressive insertion into arbitrary apps, voice cloning, and mandatory speaker enrollment.
- Do not add source separation, a second enhancement pass, or optional speaker lock to v1 unless real recordings prove the basic pipeline insufficient.

## 2. Technical Decisions and Verification Status

| Topic | Decision | Verification required |
| --- | --- | --- |
| ASR runtime | FluidAudio/Core ML only, streaming path only | Compile and exercise the exact current manager API |
| Primary checkpoint | `nvidia/nemotron-3.5-asr-streaming-0.6b` is a real multilingual NVIDIA checkpoint | Verify compatible FluidAudio-converted artifacts, supported languages, decoding and licensing |
| Core ML artifact | FluidAudio publishes Nemotron 3.5 streaming Core ML artifacts | Verify exact model release, local cache layout, target build and runtime behavior |
| Default ASR compute | CPU-only preferred; no GPU/Neural Engine default | Prove `.cpuOnly` is supported and meets real-time and latency gates on M1; never silently select another backend |
| Fallback ASR model | FluidAudio Parakeet EOU 120M or English Nemotron streaming profile | Only if primary profile is infeasible; document the product-level deviation |
| Parakeet TDT v3 | Batch/windowed, not the required streaming live path | Exclude from v1 live ASR |
| Enhancer | DeepFilterNet 3 Core ML via `DeepFilterNetCoreML` | Verify source-level API, delay, sample alignment, license, M1 CPU performance, and WER |
| VAD | FluidAudio Silero VAD on the selected front-end stream | Benchmark clean vs raw and an FSMN-VAD candidate; preserve first and last words |
| Text cleaner | S1-mini GGUF via llama.cpp | Pin the official prompt, tokenizer, revision, license and thinking-off generation format |
| Grammar | Harper Rust core via small C ABI, strictly gated | Confirm actual lint rule IDs, Unicode offsets, precision |
| Design | `DESIGN.md` latest Island specification wins | Do not revive older draggable / idle-pill descriptions |

### Material conflicts resolved

- The old plan said ASR must run on the Apple Neural Engine. The new requirement is CPU-first. Keep the CPU-first preference, but make its feasibility a Phase 0 release gate; ANE-optimized conversions are not proof of fast CPU execution.
- The old plan called the Nemotron 3.5 ID nonexistent. NVIDIA now publishes that exact model ID. It exists, but the original checkpoint is not interchangeable with an arbitrary Core ML bundle.
- The old plan's 'warm once forever' and 'pin memory' are best-effort lifecycle objectives, not operating-system guarantees. macOS may reclaim memory or recompile a model.
- The old plan's draggable Island conflicts with its later `DESIGN.md §8.18` override. The fixed notch-shaped version is authoritative.
- Never assume enhancement always improves recognition. Raw, light and full-enhancement modes must be measured against actual WER and clipping, not how pleasant audio sounds.

## 3. Architecture and Data Flow

### Layers

| Layer | Contents | Dependency rule |
| --- | --- | --- |
| L0 | `Kernel`, `Ports`, `TestKit` | Domain types and protocols only |
| L1 | Hardware, model, database, and OS adapters | Depend only on L0 |
| L2 | Audio, ASR/session, cleanup, recovery, statistics engines | Depend on L0 contracts, never concrete adapters |
| L3 | Independent SwiftUI features and view models | Depend on L0, L2 public contracts, L4 |
| L4 | Design system, icons, UI components | Design tokens and domain value types only |
| L5 | `SuperflowApp` composition root | Wires concrete adapters and all other layers |

### Dictation audio

```text
Selected microphone (Core Audio HAL)
  → callback-safe ring buffer
  → raw PCM journal + sample timeline
  → optional AEC with playback reference
  → adaptive enhancement (raw / light / DeepFilterNet 3)
  → 16 kHz synchronized audio
  → streaming VAD + speech-boundary state machine
  → continuous FluidAudio / Nemotron ASR
  → committed raw transcript in SQLite
  → Tier 0 → S1-mini → Harper → line formatter
  → insert into original focused app + update history
```

- VAD establishes segmentation and endpoint hints; it must not starve the streaming recognizer of needed context or skip an audio frame merely because a detector says silence.
- Audio always enters the journal before destructive processing. Journal writes can be asynchronous only when their bounded queue and failure policy guarantee correct ordering and detect loss.
- AEC is conditional. Without a usable far-end reference, do not invent an echo-canceled signal.

### Meeting audio

```text
Mic ─→ independent raw journal ─→ capture/enhancement/VAD/ASR ─┐
                                                               ├→ shared-clock ordered turns → cleanup → SQLite/export
System audio ─→ independent raw journal ─→ VAD/ASR/diarization ─┘
```

### Text execution paths

- Short dictation: cleanup finishes before insertion, subject to a 1.5-second stop-to-paste budget; use Tier 0 on timeout.
- Long dictation and meetings: commit raw segments and clean them incrementally during recording. Finalization must never reprocess an entire 10-hour transcript in one model call.

## 4. Repository Structure and Boundaries

```text
Superflow/
├── DESIGN.md
├── Makefile
├── docs/
│   ├── adr/
│   ├── architecture/
│   ├── runbooks/
│   ├── benchmarks/
│   └── open-questions.md
├── spikes/
├── tools/
│   ├── check-deps/
│   ├── lint-forbidden/
│   ├── gen-fixtures/
│   └── Superflowctl/
├── App/
│   ├── Superflow.xcodeproj
│   ├── SuperflowApp/
│   ├── Resources/
│   └── InferenceHelper/
├── Packages/
│   ├── L0-Core/
│   │   ├── Kernel/  Ports/  TestKit/
│   ├── L1-Adapters/
│   │   ├── AudioCapture/  SystemAudioCapture/  AudioJournal/
│   │   ├── EnhancementDeepFilterNet/  AECVoiceProcessing/
│   │   ├── VADFluidAudio/  ASRFluidAudio/  DiarizationFluidAudio/
│   │   ├── LLMLlamaCpp/  GrammarHarper/  StorageSQLite/  ModelStore/
│   │   ├── HotkeyEngine/  TextInsertion/  PermissionsKit/  Diagnostics/
│   ├── L2-Engines/
│   │   ├── AudioFrontEnd/  AudioEnhancement/  SpeechSegmentation/
│   │   ├── ASRLifecycle/  TextCommands/  TextDisfluency/  SpokenCode/
│   │   ├── TextNumbers/  TextLexicon/  TextShortcuts/  ListPlanner/
│   │   ├── TextCleanup/  TextGrammarGate/  TextLineFormat/  TextPipeline/
│   │   ├── SessionEngine/  MeetingEngine/  StatsEngine/  RecoveryEngine/
│   ├── L3-Features/
│   │   ├── FeatureIsland/  FeatureDashboard/  FeatureHistory/
│   │   ├── FeatureDictionary/  FeatureShortcuts/  FeatureMeetings/
│   │   ├── FeatureSettings/  FeatureOnboarding/
│   └── L4-UI/
│       ├── DesignSystem/  Icons/  UIComponents/
└── Tests/
    ├── Integration/  E2E/  Performance/  Soak/  Golden/  Fixtures/
```

- Keep one SwiftPM package per module and prefixed targets such as `SuperflowAudioFrontEnd`; use `Package.swift`, `Sources/`, and separately located `Tests/` in each package.
- No `Utils`, `Helpers`, `Common`, `Misc`, or catch-all shared modules. Name directories by purpose.
- One primary type per file; 300-line soft limit, 400-line hard limit; split at roughly 10 files per folder.
- No application logic in SwiftUI views. No global mutable singletons or internal `NotificationCenter` event bus. Constructor injection only.
- Dependency validator must reject imports from an invalid layer. Every port has a fake and a contract test.
- Preserve `spikes/` as throwaway experiments; never quietly ship experimental code as production adapters.

## 5. Ports and Runtime Contracts

| Port | Contract |
| --- | --- |
| `AudioSource` | Starts/stops, emits timestamped native or 16 kHz Float32 chunks, device route/silence/stall/error events |
| `AudioJournal` | Append by stream ID and sample range; flush, finalize, replay, report durability watermark |
| `SpeechEnhancer` | `prepare`, `process`, `finish`, `reset`; reports exact input/output latency and rate |
| `SpeechActivityDetector` | Chunk-wise speech probabilities and event timestamps, with resettable recurrent state |
| `SpeechRecognizer` | Load/prepare/stream, feed frames, receive partial/committed/endpoint/error events |
| `ASRRuntime` | Lifecycle states, readiness, compute policy, warm probe, session reuse, recover |
| `TextCleaner` | Cancellable bounded chunk cleanup with deadline, finish reason and diagnostics |
| `GrammarChecker` | Lint protected text spans, return precisely indexed suggestions |
| `TranscriptRepository` | Append raw, update cleaned, finalize, query, export, delete |
| `TextInserter` | Prepare target, insert safely, return verified/unverifiable/failed |
| Other existing ports | `SettingsStore`, `ModelProvider`, `SpeakerDiarizer`, `HotkeySource`, `PermissionGate` |

- Keep adapters ignorant of policy and engines ignorant of third-party implementation details.
- `AudioChunk` includes source ID, monotonic capture timestamp, sample rate, start-sample index, frame count, generation/route ID, and discontinuity flag.
- The audio front-end reports delay compensation and frame accounting; equality of emitted and input sample counts alone is insufficient to prove alignment.
- Explicit contract state covers unavailable model, device timeout, journal failure, dropped capture frames, and partially recovered sessions.

## 6. Concurrency and Real-Time Invariants

- Swift 6 complete strict concurrency. Actors for stateful services; `@MainActor` only for UI state and view models.
- Real-time Core Audio callback: no heap allocation, locks, file I/O, logging, blocking `await`, Swift actor crossing, or inference. Copy into a preallocated single-producer/single-consumer ring buffer.
- One dedicated drain task owns ordering. Every downstream stream and worker queue is bounded, instrumented, and has an explicit overflow policy.
- Never silently discard microphone audio to accommodate a slow enhancement model. Retain recoverable journaled data and mark playback/inference gaps when necessary.
- One structured task tree per recording; Escape cancels, Submit drains, shutdown finalizes safely.
- Audio time comes from monotonic host time plus sample indices; wall time is only display metadata.
- Start, stop, reset, route rebuild, and model prewarm are idempotent. A generation token rejects stale callbacks.
- Keep capture and journal scheduling independent of model execution; no priority inversion from inference workers.

## 7. Microphone Capture and Crash-Safe Journal

### Device abstraction

- Primary production path: Core Audio HAL input on the explicitly selected device. Retain `AVAudioEngine` as a measured fallback only if it proves more reliable on a particular device.
- Support MacBook microphone, AirPods/headsets, wired headsets, USB microphones, default-device changes, and sample-rate/channel changes.
- Persist device UID, never an ephemeral `AudioDeviceID`. Provide `auto` and explicit-device settings with a visible selected route.
- Reject output-only and virtual/process-tap devices as microphone inputs. Verify input channels, permissions and actual nonzero capture frames.
- Register route/default device, stream-format, alive/running and device-list listeners. Detect silent-but-running and stalled capture separately.
- Handle AirPods switching to lower-rate hands-free microphone mode, disconnection, sleep/wake, and permission revocation without corrupting session state.
- Start capture on first gesture key-down; prepare infrastructure at launch without leaving the microphone live while idle.
- Record actual gaps and changed clock generations. Do not pretend a device-switch gap is continuous audio.

### Sample pipeline

- Capture device-native rate (commonly 48 kHz) as Float32 mono or downmix as needed; validate channel topology.
- Prefer a single high-quality streaming converter with persistent FIR state. Use 48 kHz for DeepFilterNet 3, then resample to 16 kHz for VAD/ASR.
- Preserve filter group delay and model lookahead in timestamp mapping. Never rebuild a resampler on every chunk.
- Explicit end-of-stream flush: output tail, compensate delay, and never lose final phonemes.
- Capture watchdog: stalled, always-zero, overflowed, and route-rebuild paths are independently observable.

### Journal

- Store raw captured audio before enhancement: Int16 PCM, 16 kHz mono where resampled journal storage is appropriate, with a manifest preserving original clock/timebase and route gaps.
- Use 60-second files plus append-only manifest, serial writes, close-time sync, roughly 5-second periodic durability watermark, and final full sync. Recovery tolerates a torn final file.
- Approximate 16 kHz mono PCM16 storage: 115 MB/hour and 1.15 GB/10 hours per source. Meetings can double this.
- Require 3 GB free to start; warn below 1 GB. Mid-session full disk must generate an explicit 'audio no longer durable' warning, never a false zero-loss promise.
- Delete journals only after transcript verification unless user opted into retention. Record raw committed transcript separately and immediately in SQLite.
- Recovery replays journal ranges missing recognized transcript; cleanup resumes from raw committed segments without duplicating rows.

## 8. Adaptive Speech Front-End

### Required pipeline

```text
Raw microphone → optional AEC → enhancement decision → VAD + streaming ASR
        └──→ durable raw journal (independent, first)
```

- Never put a destructive filter before the only preserved copy of the input.
- The preferred VAD input is enhanced speech when that path demonstrates improved detection without losing quiet or distant speech. Keep raw/light paths as automatic safety fallbacks.
- VAD and ASR should normally consume the same aligned stream. Avoid detecting endpoints on enhanced audio while transcribing mismatched raw audio unless the offset and segmentation policy are explicitly tested.

### Enhancement candidates

| Role | Candidate | Decision |
| --- | --- | --- |
| Primary | DeepFilterNet 3 stateful Core ML (`DeepFilterNetCoreML`) | Native 48 kHz / 10 ms hop; first implementation candidate |
| Lightweight | RNNoise or comparable small denoiser | Only if lower power or lower latency is measurably useful |
| Echo + noise | FluidAudio LocalVQE or Apple voice-processing AEC | Evaluate with a real playback reference, especially in meetings |
| Severe noise + reverb | NVIDIA RE-USE, if a practical native Apple runtime exists | Research-only comparator; do not add an unsupported production dependency |
| Hard overlap | Source separation / target-speaker extraction | Post-v1 experiment, not always-on |
| Bypass | Raw audio | Mandatory, zero-model fallback and A/B baseline |

- The referenced Swift DeepFilterNet port is `kylehowells/DeepFilterNet-mlx`, linking its `DeepFilterNetCoreML` product with the `iky1e/DeepFilterNet3-Streaming-CoreML` checkpoint. Verify all signatures against the installed source before integration.
- The upstream package reports ~30 ms fixed model delay and sub-millisecond per-hop compute in a specific benchmark. Neither value is an end-to-end latency guarantee on M1.
- `SpeechEnhancer.prepare()` loads/verifies the local model before record time. Reuse model weights; reset recurrent audio state per recording/route generation.
- Run streaming 48→16 kHz conversion with persistent resampler state. No per-chunk `removeFirst` on an ever-growing array, zero-padding without accounting, or unbounded carry buffers.
- Record enhancement model revision, mode, current input UID, dropped frames and processing time as private-free diagnostics.

### Adaptive modes

- `off`: raw capture, no enhancement.
- `light`: verified low-distortion settings or lighter model where exposed.
- `full`: DeepFilterNet 3, with explicit clipping and speech-preservation checks.
- `auto` (default after validated trials): select the least aggressive mode that improves downstream recognition for the observed device/noise conditions.
- Do not automatically escalate simply because amplitude is high; a TV speaker and the owner's voice may have similar energy.
- On model failure, excessive backlog, clipping, severe artifacts or CPU pressure: switch atomically to raw or light mode with timestamp-correct queued-frame recovery.
- Never infer quality from denoiser correlation alone. Validate word error, omitted words, onset/offset clipping, double-talk and false triggering.

### Echo control and multi-speaker audio

- Use acoustic echo cancellation only when a reference stream is available and aligned; test Mac speakers at several volumes and with AirPods.
- Avoid a second denoising pass unless it wins on actual final transcripts; repeated filtering often distorts consonants.
- Target-speaker enrollment requires explicit user opt-in and local storage controls. Do not confuse VAD with speaker identification; background speech is still speech to a VAD.

## 9. VAD and Speech Segmentation

- Default: current FluidAudio Silero VAD, with the exact available Core ML model and streaming API pinned during Phase 0.
- Benchmark FSMN-VAD and other existing FluidAudio alternatives on the same corpus if they reduce music/noise false positives without clipping quiet speech; avoid integrating a second detector by default.
- Use probability hysteresis, e.g. initial speech-entry threshold 0.6–0.75 and lower speech-exit threshold, calibrated from golden recordings.
- Pre-roll: initially 300–600 ms captured before speech onset; post-roll: initially 300–600 ms after speech offset. Tune, never hard-code as universal truths.
- Min-speech and min-silence durations prevent keyboard noise or tiny breaths from creating fragments. Use explicit hangover and minimum speech duration.
- Every VAD decision maps to original sample timestamps after enhancement/resampling delay compensation.
- Distinguish utterance endpoints from ASR streaming encoder cache rotation. Do not reset the model simply because a VAD frame briefly dips.
- For long sessions, evaluate rotation after a stable pause around 30 seconds of content with a 120-second safety cap. Ensure hard rotations preserve context, trailing words and ordering.
- If VAD stalls or rejects too much actual speech, bypass gating rather than blocking ASR. The raw journal remains replayable.
- Output includes speech probability, segment start/end sample, source, confidence, detected gap and padding metadata.

## 10. FluidAudio Streaming ASR

### Model and compute policy

- Primary product choice: NVIDIA Nemotron 3.5 ASR streaming 0.6B, using FluidAudio's matching Core ML conversion, not the unconverted NVIDIA NeMo/PyTorch checkpoint.
- Force streaming inference. Do not substitute a batch TDT or offline re-pass in v1.
- Default preference: CPU only (`MLComputeUnits.cpuOnly`) for ASR. Construct once with explicit compute settings and verify effective behavior; never silently fall back to ANE/GPU.
- The published FluidAudio Nemotron conversions and benchmarks heavily emphasize ANE. CPU-only real-time throughput and supported ops on an M1 must be measured, not assumed.
- If CPU-only fails correctness or sustained real-time gates, stop and record an ADR. Present an explicit ANE opt-in or an alternative supported streaming model; do not claim the original hard constraints were met.
- The 'no GPU as default' rule applies to streaming ASR. S1-mini's separate llama.cpp Metal path remains as specified; enhancement compute is independently configured and measured.
- Set an explicit language hint for English if available in the exact Nemotron 3.5 converter; prevent special language tags leaking into final text.
- Pin the checkpoint, conversion revision, tokenizer, model SHA-256, chunk tier, and compute policy in `ModelStore`.

### Continuous streaming

- Feed ordered fixed-size frames with verified backpressure, preserve ASR decoder/encoder caches across chunks, and expose low-latency provisional partials.
- Only reset per-utterance decoder/transcript state when the API requires it; keep loaded weights and runtime objects alive.
- Finalize committed segments on verified endpoints; use a rolling journal replay cursor for recovery, not whole-session replay.
- Watchdog: if speech is present for ~8 seconds without model progress, recover recognizer state, replay bounded uncommitted audio, and avoid duplicate transcript commits.
- Meeting mode: two simultaneous streaming recognizers if measured memory and throughput permit. If not, use a documented arbitration strategy that preserves both audio streams and their timestamps.
- Expose word-level timing only if the adapter genuinely provides it; do not invent alignments.

### Streaming chunk reality

- NVIDIA lists multiple chunk tiers. Model chunk length sets a lower bound on meaningful first-partial latency; 560 ms or 1120 ms cannot promise a partial within 150 ms of the first microphone sample.
- Benchmark the lowest-latency supported FluidAudio tier on the actual M1 device, along with WER and compute cost. Default to the best tested point, not the smallest theoretical tier.
- Keep `time_to_capture`, `first_decoder_progress`, `first_nonempty_partial`, `endpoint_latency`, and `inference_latency` as distinct metrics.

## 11. No-Rewarm Runtime Lifecycle

### State machine

```text
unloaded → loading → compiling → warming → ready
                          ↘ failed / degraded
ready → recording → ready
ready → interrupted / evicted → recovering → ready
```

- `ASRLifecycle` is injected, long-lived, and owned by the composition root or the inference helper. Never create it on every hotkey event.
- On app launch, prepare model cache and start asynchronous load/compile/prewarm off the main thread. Do not start the microphone while idle.
- Run a real dummy inference with valid frame shape to initialize the compute graph and decoder, then clear dummy transcript/cache state.
- Keep weights/model and reusable stream factories resident as long as the OS permits; reset only per-session state. Do not call load or compile again on normal session transitions.
- Prefer `mlmodelc`/compiled model assets and checksum-validated local paths. Never fetch or convert a model while the user is recording.
- Set compute units explicitly when creating the model, and preserve that policy through helper restarts.
- The system may reclaim memory after pressure, sleep or updates; detect actual readiness, restore silently, and preserve captured audio if inference is briefly unavailable.
- Suppress routine internal 'warming CPU/GPU' UI/log noise after readiness. Never label an unready model as ready; show a concise actionable error if the app cannot process audio.
- Keep the prewarm idempotent and serialized: concurrent app launch, settings refresh or first hotkey must not trigger parallel model loads.
- Model retention is best-effort, not `mlock` of huge allocations or a promise against macOS paging. Avoid an always-spinning keepalive that drains battery.

### Hot path

- Hotkey → capture immediately → queue frames to ready recognizer → emit partials → Tier 0 / cleanup → insert.
- If the key arrives before model readiness, capture and journal bounded audio, then replay into the hot stream. No lost first phrase and no fake partial.
- Keep capture independent of recognition and cleanup prewarm. Prioritize interactive ASR over background cleanup work.
- If S1-mini or Harper is cold, use Tier 0 without delaying ASR. Prewarm separate model runtimes according to measured memory headroom.

### Performance goals, not assertions

| Metric | Initial target | Caveat |
| --- | --- | --- |
| Launch → ASR ready | Under 2.5 s on M1 | Measure including model load, compile and sample inference; may require revision |
| Key-down → capture | p95 under 100 ms | Hot model is irrelevant if device startup is slow |
| First nonempty partial | As fast as the selected chunk tier allows | 150–200 ms only if the real tier and runtime support it |
| Sustained ASR RTF | Under 0.5 | Evaluate worst-case CPU-only M1, thermal load and two-stream mode |
| Normal warm sessions | Zero model reloads | Validate with instrumentation; OS interruptions are exceptions |
| 30-minute stability | No increasing latency or unbounded RSS | Inspect heap, graph caches and queue depth |

- Report medians/p95/p99 by model, device type, compute mode and chunk tier. Any deadline not met is a benchmark finding, not something to hide by removing a UI label.

## 12. Text Pipeline: Exact Stage Order

All stages take a draft with ordered words, protected spans, timestamps and context. Failures return the input plus a local diagnostic; no stage may make the transcript disappear.

1. `TextCommands`: optional explicit speech commands.
2. `TextShortcuts`: whole-utterance or explicit inline expansions, inserted verbatim and short-circuited.
3. `TextDisfluency`: conservative repeated-token and filler cleanup; preserve meaningful repeats and protected content.
4. `SpokenCode`: assemble filenames, paths, extensions and context-qualified emails; optional Code Speak.
5. `TextNumbers`: cardinals, digit sequences, decimals, ordinals, years, dates, currency, percent and units.
6. `TextLexicon`: user corrections and curated technical terms; canonical form gets protected/glue metadata.
7. `ListPlanner`: detect explicit enumeration, split intro/items/tail before the language model.
8. `LongFormCleaner`: S1-mini with validated protected content, bounded chunking and retries.
9. `FinalPolish`: punctuation spacing, standalone `I`, date commas and conservative casing outside protected spans.
10. `TextGrammarGate`: permitted high-confidence Harper suggestions only.
11. `TextLineFormat`: paragraph length and preserved list/command line breaks.

- Implement a `Word` value type with `lead`, `core`, `trail`, `protected`, `glue`, and pause metadata. Preserve punctuation at boundaries.
- Lexicon terms, code and numeric literals are asserted verbatim after S1-mini. Never silently 'fix' damaged tokens after generation; reject the damaged result.
- Each deterministic stage must be idempotent, bounded in output length, safe on empty input, and protected-span-preserving.
- Existing `NumbersStage` can remain a compatibility adapter around reference `TextNumbers.apply`; do not create competing number policies.

### Number formatting

- Evaluate FluidAudio's text-processing/ITN library against fixtures before writing additional custom logic.
- Correctly format spoken numbers, digit runs, clocks, versions, dates, percentages, units, years, and USD/EUR/GBP/INR.
- Support Western and Indian digit grouping including lakh and crore; preserve IDs, ZIP codes, phones and version strings.
- Configurable small-number policy and large-number style: `two hundred thousand dollars` → `$200k` by default or `$200,000` if preferred.
- Examples and ambiguities must be covered by negative tests; do not rewrite numerals already protected.

### Dictionaries and shortcuts

- Lexicon entries: ID, term/correction kind, triggers, canonical form, enabled, source. Longest whole-token match wins; no phonetic/fuzzy substitutions in v1.
- A small curated technical dictionary (about 150 entries max) ships with false-positive goldens, especially for ordinary words that resemble technical names.
- Shortcuts match whole utterance by default, with opt-in inline mode; preserve literal multiline Markdown, limit expansion to 200 KB, and skip later formatting.
- Provide import/export and warnings for ambiguous triggers. No automatic learning in v1.

## 13. S1-mini Cleanup and Long-Form Scheduling

### Model contract

- One S1-mini GGUF model per process; llama.cpp bridge with bounded reusable contexts. Metal offload is allowed for this text-cleanup path.
- Pin the official S1-mini system prompt, revision, special-token and control-line format from its model card; use a file hash test.
- Control line consists only of the trained `Styling`, `Structure` and `Context` fields. Do not append invented carry-state fields. Thinking off, greedy decode, temperature 0.
- Clamp app presets at the adapter boundary. ListPlanner handles list continuity before the model; lists must not cross a chunk seam.
- Size `max_new_tokens` to input, bounded by a configured cap, and detect actual stop/length finish reason.

### Chunking and workers

- Count tokens with the model tokenizer. Set target to 55–60% of the measured safe length (provisional 600-token target / 850-token cap until Spike B).
- Split by committed ASR segment, VAD pauses, sentence, then clause. Never split mid-word, protected expression or speaker turn.
- A bounded worker pool prioritizes interactive chunks over long-session background chunks. Benchmark N = 1, 2, 3, 4, 6, 8; choose best p95 latency and throughput without memory thrash.
- Keep one loaded model and reusable contexts. Apply cancellation-aware queues. Check cancellation between tokens and prefill batches.
- Deadlines after obtaining a context: interactive 1.5 s and background 30 s per chunk, with explicit fallback on breach.
- Persist raw and Tier 0 text before background cleanup so a crash can resume uncompleted work.

### Integrity guard

- Reject output if it loses a protected literal; omits the final content words; generates unsupported information; ends because of a token cap; or suffers unexplained length collapse.
- Empty output is permitted only for genuinely content-free filler utterances under an explicit policy.
- Retry failed chunks by splitting at a safe boundary up to depth 3. Otherwise persist and use the complete Tier 0 text, marked `fallback`.
- Assemble only in order using bounded overlap alignment; no duplicated/missing seam words and no quadratic whole-transcript rescans.
- Keep the model context prompt constant over chunks, using overlap words rather than an untrained extra prompt section.
- No second LLM cleanup pass or whole-document consistency pass in v1.
- Long-session finalization waits only for bounded remaining work; a background chunk that exceeds the stop deadline may remain marked pending and resolve later without blocking access to raw text.

## 14. Harper Grammar Gate

- Build `Rust/harper-ffi` into a static library/XCFramework with minimal create/lint/add-dictionary/free functions. Swift `GrammarHarper` implements the `GrammarChecker` port.
- Define offsets precisely across UTF-8, Swift grapheme clusters and UTF-16; test emoji, combining marks and non-Latin punctuation.
- Allowlist exact confirmed rule categories only: candidate spelling, agreement, repeated words and article selection. Disable style, readability and creative word-choice rules.
- Never touch protected spans. Apply only suggestions and reject a whole chunk if changes exceed 3% of words.
- Require at least 98% precision per enabled rule category on ~200 dictation-style golden sentences; otherwise disable the category.
- Cap linting to 50 ms per chunk; gate must be idempotent. No external Harper language-server process.

## 15. Paragraph and Line Formatting

- Default: minimum 25 words, preferred break at 35, hard maximum 45, blank-line paragraphs; each is configurable.
- Split on true sentence boundaries, not in URLs, email addresses, abbreviations, decimal numbers, filenames or `Next.js`.
- At 25–35 words break at the next sentence end; at 35–45 break when safe. For extremely long sentences use a clause boundary, then a word boundary at the hard cap.
- Preserve intentional newlines from lists, explicit commands and code. Do not reflow or duplicate list items.
- Avoid a tiny trailing paragraph under eight words if it can merge without exceeding the hard maximum.
- Maintain incremental carry state so streamed and whole-text formatting produce identical outputs.
- Optional final period, trailing space, spacing normalization, sentence casing; defaults preserve short search-box dictation.

## 16. SQLite Persistence and Recovery

- Use GRDB via repository ports, WAL mode, `synchronous=NORMAL`, foreign keys, busy timeout, serialized writer and concurrent readers. A hand-written sqlite3 adapter needs its own ADR.
- Database: `~/Library/Application Support/Superflow/Superflow.sqlite`. Versioned migrations tested from each old schema; back up before migration, quarantine corruption after failed integrity check.
- Tables: `sessions`, `segments`, `speakers`, `daily_stats`, `lexicon_entries`, `shortcuts`, `settings`, plus schema/migration metadata and FTS5 transcript search.
- Each segment records stream/source, stable index, sample/time range, speaker ID, raw text, Tier 0 text, final cleaned text, model version, cleanup state and recovery provenance.
- Commit raw recognized segments immediately; cleaned results replace only that segment. Make retries idempotent with stable IDs/upserts.
- On launch, identify unfinished sessions, replay journal ranges without committed text, resume cleanup, and surface recovered text with a copy action.
- User controls transcript retention, raw-audio retention, optional no-history mode and hard deletion. Respect them for backups, recovery artifacts and FTS indexes.
- Memory must remain O(1) with respect to recording duration; use paged database reads and segment-local buffers.

## 17. Hotkeys and Session State Machine

### Capture input

- Passive event tap watches modifier changes; active swallowing tap exists only while a session needs Enter/Escape interception.
- Verify Input Monitoring, Accessibility and secure-input behavior by exercising the actual APIs. Restart disabled event taps after timeout, sleep/wake or configuration change.
- Distinguish Fn/Globe from key combinations, and right Command from left; never steal normal keyboard shortcuts.
- Onboarding explains macOS Globe/Fn conflicts and provides a practice exercise.

| Gesture | Action |
| --- | --- |
| Hold Fn at least 200 ms | Push-to-talk; release submits |
| Double-tap Fn within 350 ms | Hands-free dictation |
| Fn tap or Enter while hands-free | Submit |
| Escape during dictation | Cancel, discard, do not paste |
| Hold right Command alone at least 600 ms | Latch meeting capture |
| Double-tap right Command | Start meeting |
| Right Command tap or Enter during meeting | Finalize |
| Escape during meeting | Cancel |

- Speculative capture starts at the first key-down. A single unpaired tap is canceled after the window without leaking text.
- Pure `GestureRecognizer` consumes events and monotonic timestamps, enabling exhaustive transition tests.
- Session states: `idle → preparing/ready → recording → finalizing → inserting → complete`, plus `cancelled`, `degraded` and `failed` transitions. Exhaustive state switches and explicit timeouts.
- Keep background ASR readiness separate from the user-visible recording state. Capture can start before inference is ready.

## 18. Safe Text Insertion

- Prepare the frontmost app/focused target at recording start; invalidate on app or focus changes and verify target again before insertion.
- Prefer verified Accessibility editing for confident text fields, otherwise safe clipboard + simulated paste, then Accessibility recovery. Secure/non-editable controls must never be modified.
- Snapshot all clipboard items and types, write a transient/concealed text item, restore only if no intervening clipboard modification occurred.
- Flush pending clipboard restores before each new insertion. Resolve Cmd+V by active keyboard layout; mark synthetic events so hotkey listeners ignore them.
- Verify paste by expected field value where possible; use character-count checks only when full value is unavailable. Report `unverifiable` rather than calling a successful unobservable paste a failure.
- Serialize insertions; never paste into SuperFlow itself unless explicitly selected as a practice control.
- Honor Secure Input: skip forbidden simulated keys and use supported fallback.
- Island is non-activating so the original app retains focus. If insertion fails, retain finalized text in history and expose Copy; clipboard-only deadline fallback must actually write the clipboard before claiming it did.
- Stop-to-insertion deadline: 8 seconds ultimate recovery cap; short dictation uses the stricter 1.5-second text-ready policy.
- Progressive typing/rewriting partial output in arbitrary apps remains post-v1.

## 19. Meetings

- Record mic and system audio independently with a shared monotonic clock and distinct journal/recognizer paths.
- Use Core Audio process taps when verified; ScreenCaptureKit audio-only fallback where appropriate. Test Zoom, Google Meet and macOS permissions on the target OS.
- Mic channel is `You` unless the user renames it. FluidAudio streaming diarization labels the system channel; verify model speaker limits rather than assuming unlimited speakers.
- Use AEC if there is a reference and measurable improvement. Otherwise deduplicate probable self-echo only with time-aligned high-similarity evidence; do not delete legitimate simultaneous speech.
- Merge turns by aligned timestamps, preserve stable speaker IDs, never mix speakers in a cleanup chunk, and mark lost-stream intervals explicitly.
- Failure of system audio continues mic-only with a visible gap; failure of one recognizer cannot destroy the other channel's journal or raw transcript.
- Markdown export: title/date/duration/participants plus timestamped speaker turns. JSON export: `schemaVersion`, metadata, `speakers[]`, `segments[]` with start/end/source/speaker/raw/final text.
- `Copy as Markdown`, `Export Markdown`, and `Export JSON`. No AI summaries in v1.

## 20. Feature Requirements

### Dashboard

- Total finalized dictation words, estimated time saved `max(0, words / typingWPM - speakingTime)` with unit conversion, configurable default typing rate 40 WPM.
- Speaking speed uses VAD-detected speech duration, not wall time. Daily streak uses stored local day to survive timezone/DST changes.
- 53×7 contribution calendar over last year with five intensities; query preaggregated `daily_stats`, not transcript rows.
- Meetings excluded from personal dictation statistics by default.

### History

- FTS5 full-text search, paginated results, keyboard navigation, copy, delete with undo toast, raw/cleaned text toggle, session metadata and recovery status.

### Dictionary and Shortcuts

- Create/edit/search/delete, import/export JSON, exact trigger matching and clear warnings for common-word collisions.

### Settings

- Recording gestures, input UID/auto selection, microphone route status, ASR model and explicit compute choice, enhancement off/light/full/auto, VAD diagnostics, cleanup and Harper toggles, number style, paragraph rules, typing speed, meeting self-name, retention, privacy, start at login and local diagnostics export.
- Advanced toggles must never pretend experimental speaker separation or target lock is included in v1.

### Menu bar

- SwiftUI `MenuBarExtra` for Open, Start/Stop, Settings, Quit; restore window state and follow the repository's Dock visibility behavior.

## 21. UI and Design Contract

- `DESIGN.md` is authoritative for color, typography, spacing, motion, icons, hover, focus and all notch geometry. Map tokens to code; log unspecified details rather than inventing design.
- Hugeicons only for custom UI (except OS-mandated native symbols). Typed icon wrapper and vector assets; verify redistribution license.
- Interactive custom elements use one reusable pointing-hand cursor implementation; disabled controls do not. Lint forbids raw clickable controls in feature packages outside the wrapper.
- Every component supports keyboard use, VoiceOver, reduce motion, light and dark appearance, and native focus rings.
- Island: follow latest `DESIGN.md §8.18` fixed 520×128 notch-shaped opaque-black window, no drag, no persisted location, no idle pill, non-activating. Earlier draggable Dynamic Island prose is superseded.
- Keep Island and main-window SwiftUI hierarchies separate; opening one never destroys the other.
- Main window: standard resizable window and sidebar for Dashboard, History, Dictionary, Shortcuts, Meetings and Settings.
- Never show generic warm-up messages during normal ready-state recording. If the model cannot process input, show a real concise failure state, not misleading readiness.

## 22. Permissions, Distribution and Privacy

- Permissions: microphone, Input Monitoring, Accessibility and meeting system-audio recording only when needed. Recheck live and verify functionality rather than treating a flag as success.
- Onboarding: welcome, permissions, Globe/Fn conflict guidance, resumable checksum-verified model download, device test, optional noise-mode selection, practice dictation, meeting setup.
- No sandbox requirement in the original design due to event taps/process capture; validate actual entitlement/signing needs for macOS 15+ in the chosen distribution model.
- Consistent bundle ID/signing identity from early builds, hardened runtime, Developer ID notarization, DMG distribution, launch at login through `SMAppService`.
- Updating via Sparkle or another signed feed requires an ADR; no self-updating binaries without verification.
- All inference offline after model installation. License/notices screen covers FluidAudio, Nemotron 3.5 (including OpenMDW terms), enhancement model, S1-mini, llama.cpp, Harper, and UI assets.
- Diagnostics never include text, audio, prompts or protected content. Encryption/retention policy must cover on-disk journal and database backups.

## 23. Verification and Test Matrix

### Required suites

| Suite | Main assertions |
| --- | --- |
| Unit/contract | Real-time ring, lifecycle state, port contracts, word/text stage properties |
| Audio goldens | Known sample counts, resampler phase/delay, raw journal preservation, flush tail, device gaps |
| VAD | Onset/offset accuracy, noise/music false positives, misses, padding and endpoint delay |
| ASR | WER/CER on the same recordings with raw/light/full enhancement, each device and backend |
| Cleanup goldens | Numbers, Indian grouping, code, dictionaries, lists, protected text, no additions/omissions |
| Integration | ReplayAudioSource → front-end → streaming ASR → SQLite → text pipeline → fake insertion |
| E2E | Hotkeys, focus, clipboard restore, Island states, main window, permissions |
| Soak | 1 h nightly, 10 h weekly, real-time overnight before release |
| Fault injection | kill -9, disk full, route switch, capture stall, buffer overflow, ASR hang, model eviction, cleaner crash, source loss |

### Audio evaluation corpus

- Record consented/local reference speech on MacBook mic, AirPods, wired/USB input where available.
- Conditions: quiet, fan, keyboard, café chatter, TV/music, reverb, low-volume speech, far-field speech, headphones vs laptop speakers, two simultaneous talkers.
- Include device reconnect during speech, sample-rate changes, and long quiet stretches.
- Blindly compare raw vs light vs enhanced transcript WER/CER, clipping, insertion/deletion rates, false VAD activation, missed word beginnings/ends, latency, CPU/RSS/power.
- Accept `auto` enhancement only if it improves chosen primary metrics on held-out recordings without meaningful regressions to quiet speech.

### Long-run acceptance

- Streaming buffers and memory O(1) in session length. 10-hour RSS growth target under 50 MB after warm-up, with known system cache variability recorded.
- Zero silent audio/sample loss. Any dropped frames have explicit counters and gap markers; disk-flush window remains a documented durability limitation.
- Compare accelerated replay and wall-clock processing for transcript row ordering, unique segment IDs, and segment coverage. Exact ASR words need not be identical across nondeterministic runtimes.
- Recovery restores every flushed/journaled frame and committed raw segment without duplicate rows; the most recent ~5 seconds may be at risk per sync policy.
- Every chunk reaches cleaned/fallback/pending state. Final text remains accessible even if background cleanup misses its deadline.
- A model-only or UI-only test cannot substitute for real-device field tests. Record measured results in `docs/benchmarks/`.

## 24. Observability and Performance Budgets

- `os.Logger` category per module and signposts around capture, journal, enhancement, VAD, ASR, text stages, insertion, and recovery. No user content in logs.
- Export sanitized per-device timing summaries and model/config revision: p50/p95/p99, queue age, deadline misses, ring overflows, audio discontinuities, WER on consented fixtures, RTF, RSS, CPU, energy.

| Budget | Target | Meaning |
| --- | --- | --- |
| Key-down → actual capture | p95 <100 ms | Includes input-device startup |
| Stop → paste, dictation ≤30 s | p50 <700 ms, p95 <1.5 s | Tier 0 fallback at deadline |
| Stop → raw final, any duration | <5 s | Assuming recognizer caught up; measure failures |
| First nonempty partial | Chunk-tier-derived p95 | Do not claim 150–200 ms without proven 80/160 ms tier |
| End-to-end enhancement | Bounded hop compute; fixed delay reported | Measure M1 and input device |
| Streaming ASR throughput | RTF <0.5 sustained | CPU-only and dual-stream separately |
| Idle load | Near-zero CPU, no open mic | Models can remain loaded without polling |
| 10-hour session | No unbounded queues/RSS, no unreported gaps | Capture reliability outranks cosmetic speed |

- A target that fails on M1 becomes a documented release blocker or owner-approved ADR; do not conceal failure by deleting metrics, hiding startup work, or changing the test.

## 25. Implementation Phases and Exit Gates

### Phase 0 — Verify Dependencies and Measure Reality

- Spike A: confirm Nemotron 3.5 FluidAudio streaming artifact/API, CPU-only execution, supported chunk tiers and M1 sustained RTF. Compare fallback streaming model only if necessary.
- Spike B: DeepFilterNet 3 Swift/Core ML integration, 48↔16 kHz conversion, model delay, CPU/ANE/GPU capability, raw-vs-enhanced ASR WER on real noisy/quiet recordings.
- Spike C: Silero vs optional FSMN, hysteresis/padding and initial-word preservation; test AEC with speaker playback.
- Spike D: HAL mic selection, AirPods mode changes, sample-rate/device switches, silence/stall alerts, correct timestamped gaps.
- Spike E: S1-mini official prompt, truncation sweep 300–1100 tokens, Metal context count and cancellation responsiveness; Harper ABI and ITN viability.
- Spike F: two recognizers/diarization, Core Audio process-tap vs ScreenCaptureKit with actual meeting apps.
- Spike G: Fn/right Command gestures, permissions and non-activating insertion target.
- Exit: ADRs and an evidence table of exact model revisions, measured M1 latencies, WER and unresolved blockers. No locked performance claim without measurements.

### Phase 1 — Skeleton and Contracts

- Create packages, `Kernel`, `Ports`, `TestKit`, `Makefile`, dependency lint, `DESIGN.md` token map, Hugeicons adapter and CI.
- Exit: `make verify` green; intentionally invalid dependency rejected.

### Phase 2 — Audio Capture, Journal and Front-End

- HAL selection, route monitor, callback-safe ring buffer, raw journal, streaming resampler, DeepFilterNet adapter, adaptive mode and VAD/segmenter.
- Exit: headless CLI captures and replays mic; device changes and crashes preserve timestamped audio; enhancement bypass works.

### Phase 3 — Streaming ASR and Persistent Readiness

- FluidAudio Nemotron adapter, model registry/store, explicit CPU-first compute, `ASRLifecycle.prewarm`, cache/session reuse, partials, watchdog, journal replay.
- Exit: cold and warm timings recorded; consecutive dictations trigger no new model loads; real M1 RTF/latency gates evaluated.

### Phase 4 — Deterministic Text

- Commands, shortcuts, disfluencies, SpokenCode, numbers, dictionary, ListPlanner, FinalPolish and line formatting.
- Exit: golden/property suites pass; incremental equals batch line formatting.

### Phase 5 — Model Cleanup and Grammar Gate

- llama.cpp bridge, S1-mini prompt, bounded worker pool, chunk planner, overlap seam, guard/retry/fallback and gated Harper.
- Exit: protected literals unchanged, no content damage on goldens, failures recover without blocking later chunks.

### Phase 6 — Hotkeys, Insertion and Island

- Gesture state machine, live permissions, target preflight, safe insertion, finished `SessionEngine`, Island according to `DESIGN.md`.
- Exit: real Fn dictation into TextEdit, Notes, browsers, Slack, VS Code and Terminal; Escape cancels; focus is preserved.

### Phase 7 — Storage, Main Window and Settings

- GRDB, migrations, dashboard, calendar, history, dictionary, shortcuts, input/enhancement/compute settings, onboarding and menu bar.
- Exit: every feature persists after restart; raw/final history is recoverable and searchable.

### Phase 8 — Meetings

- System audio, diarization, two-stream scheduling, echo mitigation, speaker timeline, rename and export.
- Exit: real 60-minute Zoom/Meet session with correct source separation and valid Markdown/JSON.

### Phase 9 — Hardening and Distribution

- Evaluate moving model runtimes to `InferenceHelper` XPC for crash isolation without forcing rewarm on normal sessions. Complete soak/fault tests, signing, notarization and model/license packaging.
- Exit: all section 24 performance reports and section 23 tests pass, or an explicit owner-approved exception exists.

### Post-v1

- Progressive insertion, opt-in target-speaker lock, separation for severe overlapping talkers, adaptive correction learning, optional offline re-pass, larger dictionaries and expanded language UI.

## 26. Definition of Done

- All original product features remain: dictation, Island, dashboard/graph, history, dictionaries, numbers/currency, shortcuts and meeting export.
- Audio front-end is measured, recoverable and device-agnostic; VAD segmentation preserves words and improves or matches the selected baseline.
- FluidAudio Nemotron 3.5 streaming is genuinely streaming with an explicit verified compute policy; no silent backend/model substitution.
- Regular warm sessions do not reload models; startup and first-partial numbers are measured, not assumed.
- S1-mini is fast, bounded and content-preserving; Harper only applies verified high-precision corrections.
- 1-hour/10-hour tests, route change, forced kill, disk full, ASR stall, model pressure and paste failure demonstrate fallback and recovery.
- `make verify` green; no forbidden dependencies, no file above 400 lines, no warnings.
- All custom icons and pointer behavior match `DESIGN.md`; the non-draggable Island never steals focus.
- Signed/notarized build installs cleanly, downloads models with verification, and runs completely offline afterward.

## 27. Owner Decisions and Default Values

| Decision | Default |
| --- | --- |
| Meeting start gesture | Right Command hold latches after 600 ms; double-tap also starts |
| Idle Island | Hidden; fixed notch-shaped panel, no dragging |
| Pause button | Not in v1 |
| Partial insertion into target apps | Island partials; paste on submit |
| Large number formatting | Abbreviated currency (`$200k`), configurable full style |
| Paragraph break | Blank line, configurable single newline |
| Meeting statistics | Excluded from dictation dashboard |
| Enhancement | Auto after measured A/B validation; raw fallback mandatory |
| ASR compute | CPU-only preference, subject to a hard M1 feasibility gate |
| Transcript/journal retention | Configurable; choose documented default before release |
| Product name | SuperFlow is a working name |

## 28. Primary References

- [FluidAudio repository](https://github.com/FluidInference/FluidAudio)
- [FluidAudio Nemotron streaming documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/Nemotron.md)
- [FluidAudio Nemotron multilingual documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/NemotronMultilingual.md)
- [FluidAudio current ASR/VAD benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- [FluidAudio Silero VAD documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/VAD/GettingStarted.md)
- [NVIDIA Nemotron 3.5 ASR checkpoint](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)
- [NVIDIA Nemotron ASR streaming model card](https://build.nvidia.com/nvidia/nemotron-asr-streaming/modelcard)
- [DeepFilterNet Swift/Core ML runtime](https://github.com/kylehowells/DeepFilterNet-mlx)
- [DeepFilterNet 3 streaming Core ML checkpoint](https://huggingface.co/iky1e/DeepFilterNet3-Streaming-CoreML)
- [Apple Core ML compute-unit configuration](https://developer.apple.com/documentation/coreml/mlcomputeunits)
- [S1-mini GGUF](https://huggingface.co/superwhisper/s1-mini-GGUF)
- [Harper grammar engine](https://github.com/Automattic/harper)

Recheck exact revisions, release compatibility and redistribution terms during Phase 0. Documentation-derived performance numbers are not SuperFlow benchmarks.
