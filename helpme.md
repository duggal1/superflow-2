# Help requested: Superflow GPU startup and streaming latency

I am implementing Superflow, a local macOS dictation app, and I am stuck on the remaining Core ML startup delay. Please review the evidence below and recommend the smallest supported fix. You do not have repository access; this document contains the relevant architecture, behavior, measurements, and unanswered questions.

## What the owner needs

1. The Nemotron model is prepared on the GPU before normal dictation begins. Starting a dictation with the resident model must take one second or less, preferably much less. The owner also wants subsequent app launches ready within one second, instead of the observed 10–20 seconds.
2. Listening, streaming transcription, cleanup, and stop-to-insert must be as fast as the existing hardware and model permit. We need measured latency, without losing words or weakening cleanup acceptance checks.
3. Nemotron streaming must be the default throughout recording. Do not substitute batch transcription, cloud inference, another model, or a different inference runtime.
4. Follow supported FluidAudio and Apple APIs. Prefer an ordinary lifecycle or configuration correction over a custom inference implementation.

Please distinguish these goals: a new recording with an already resident model, a new process loading cached artifacts, and the first-ever compilation. They have different costs. Downloaded files and compiled artifacts do not establish that a model instance remains resident after its process exits. We have not demonstrated one-second readiness for a fresh process.

## Constraints and environment

| Item | Current implementation |
| --- | --- |
| Product | Native SwiftUI/AppKit app, macOS 15+ deployment, Swift 6 strict concurrency |
| Measurement host | Apple M1, 8 GB unified memory, macOS 27.2, Swift 6.4 |
| ASR | Nemotron 3.5 ASR Streaming 0.6B, profile ID `nemotron-3.5-asr-streaming-0.6b` |
| ASR runtime | FluidAudio **0.17.7**, revision `503b4bd1bbf7220882de39fe8ae6716aae4132da`, through Core ML |
| Active model directory | `~/Library/Application Support/Superflow/Models/FluidAudio/nemotron-multilingual/latin/2240ms/` |
| Default compute policy | `MLComputeUnits.cpuAndGPU`; diagnostic overrides exist for CPU, GPU, ANE, and all units |
| Input | 16 kHz mono Float32 audio |
| Cleanup | S1-mini by Superwhisper, Q4_K_M GGUF, llama.cpp `b11556`, in an XPC helper |
| Enhancement | DeepFilterNet 3 through Core ML, CPU+GPU; optional noise suppression |
| Persistence | SQLite WAL, durable audio journals, bounded recording queues |

Keep the ASR model, parameter count, cleanup model, and runtimes unchanged. Treat a different chunk-tier export or moving ASR into another process as a proposal requiring explicit discussion, rather than silently implementing it. Preserve the pinned cleanup prompt, deterministic generation, content guards, privacy, cancellation behavior, and last-safe-text fallback. Never log user transcripts or audio.

Core ML's CPU+GPU configuration permits both devices; it does not prove every operation executes on the GPU. The owner wants GPU as the default, but pasteboard and keyboard-event delivery are CPU/OS operations. Please identify the useful inference parallelism rather than proposing GPU acceleration for Cmd+V itself.

## Current startup and residency behavior

The composition root owns one long-lived `FluidAudioRecognizer` actor. App launch starts ASR preparation and cleanup preparation without waiting to present the main window. Closing the main window leaves the menu-bar app running.

The ASR path is:

```text
AppCoordinator.startModelPreparation
  -> SessionEngine.prewarm
     -> recognizer.warmUp(exact profile)
        -> check installed artifacts
        -> join an existing preparation task, or create one
        -> FluidAudioEngineLoader.load
        -> return the prepared manager to the idle pool
     -> also await optional enhancement preparation
```

The recognizer records prepared profiles and deduplicates concurrent ASR initialization. Its pool retains at most two idle managers per profile, supporting separate microphone and system-audio streams for meetings. A completed stream resets its healthy manager and returns it to the pool; it does not reload the model for the next dictation. Unhealthy managers can be replaced by the stall-recovery path.

Recording-time warm-up checks local artifact existence and loads locally. ASR downloading is a separate setup/settings path, not part of every launch or recording. Already prepared profiles return immediately.

The relevant model creation is equivalent to:

```swift
let configuration = MLModelConfiguration()
configuration.computeUnits = .cpuAndGPU
let manager = StreamingNemotronMultilingualAsrManager(configuration: configuration)
try await manager.loadModels(from: installedDirectory)
```

The installed directory contains `encoder.mlmodelc`, `decoder.mlmodelc`, `joint.mlmodelc`, `decoder_joint.mlmodelc`, `metadata.json`, and `tokenizer.json`. The fused decoder/joint exists. The optional `decoder_joint_noencproj`, `decoder_joint_argmax`, and `joint_noencproj_batched` assets were absent in the inspected installation. Do not assume they can simply be enabled with a flag.

The pinned FluidAudio implementation loads model components sequentially, creates states and reusable buffers, and runs internal per-model warm-up predictions before `loadModels` returns. Therefore our outer model-load timer includes initialization and internal warm-up. It is not a pure file-read timer. The multilingual manager computes mel features in Swift rather than running the bundled Core ML preprocessor.

We intentionally avoid an additional application-level synthetic-silence inference pass. Earlier attempts were removed after a Core ML/MPSGraph tensor-shape/rank exception associated with the streaming/prefetch path. Do not recommend another dummy streaming pass without addressing that risk and the vendor's existing warm-up.

## Default streaming path and potential latency floor

The application catalog selects the streaming manager by default. There is no batch-ASR substitution in this path. The adapter appends each incoming buffer, drains pending samples into `manager.process(samples:)`, forwards partial-transcript callbacks, and calls `manager.finish()` only to flush the final tail. It uses `manager.reset()` between recordings.

The application wrapper's `getPartialTranscript()` currently returns an empty string; live partials are delivered through the registered callback instead. Please check whether that is sufficient for the installed manager/protocol contract, without assuming the empty getter means streaming is disabled.

Actual installed metadata:

```json
{
  "sample_rate": 16000,
  "chunk_mel_frames": 224,
  "att_context_size": [42, 13]
}
```

The selected processing tier is **2240 ms**. A fast inference on already collected audio is different from the time needed to accumulate live audio and satisfy encoder lookahead. Please determine the real first-partial latency floor from this metadata and the compiled graph. Do not promise subsecond live partials merely because a full chunk computes in about 200 ms.

Capture and recognition use separate lanes, with a bounded recognition relay. Capture starts before a cold model finishes preparation, but session startup still awaits recognition readiness and can enter a visible warming state. This is not immediate cold readiness.

ASR segments are committed at final stop, at a pause of at least 600 ms after a segment reaches 30 seconds, at a 120-second hard cap, or at native endpoint events where supported. This Nemotron profile is cataloged without native endpointing. Partial callbacks are live, but **cleanup normally receives committed segments**. Consequently a short dictation can stream ASR while still deferring its cleanup until Stop.

Stop currently drains captured audio, drains recognition, finishes ASR, persists the final segment, waits for cleanup, assembles safe text, finishes the archive, finalizes storage, and then inserts. The `session.stop.ms` metric is recorded before the insertion call, so it does not measure the complete stop-to-visible-paste interval.

## Measurements actually observed

These are local diagnostics, not evidence of a 10× product speedup. ASR and paste end-to-end latency have not been measured together.

| Check | Observation | Limits |
| --- | --- | --- |
| ASR preparation after disk space was restored | 23.22 s in one fresh-process run | Includes vendor warm-up and VAD preparation; not a complete GUI-app launch |
| Subsequent fresh CLI processes loading ASR | 10.19, 12.66, 8.37, 8.30, 8.53 s; median **8.53 s** | Five runs; OS/device caches were not purged; no controlled source-code A/B |
| Separate component-load probe, CPU+GPU | Encoder **14.148 s**; decoder 0.277 s; joint 0.094 s; fused decoder/joint 0.334 s | Separate run/cache state; do not add these to another run's timings |
| Acquiring a stream from the resident pool | 0.4, 1.7, 0.4, 0.4, 0.7 ms | Stream acquisition, not microphone-open or first-word latency |
| First feed with real, already collected audio | 198.8–215.9 ms across those five processes | Roughly 2.2-second fixture, not paced live speech |
| Warm ASR fixture, five measured iterations | Median 12.3× real time; about 182 ms per feed | Excludes cleanup, journal, UI, and insertion; reported 8 words and no recognition failures |
| Fixture ASR finish | Approximately 0–1 ms | This fixture leaves little tail work; not a representative stop-to-paste result |
| Live cleanup functional test | Load/prewarm 2.026 s; two fixed examples 1071 ms and 441 ms | GPU, two contexts; one functional run, not a benchmark distribution |
| Live cleanup cancellation | Returned CancellationError about 368 ms after cancellation | One observation; not a worst-case bound |

Initially the disk was effectively full and source/profiling writes failed. Those early measurements are not a clean performance baseline. Space was subsequently freed. A process sample caught Core ML inside MPSGraph resource loading, but we have not isolated file I/O, graph reconstruction, specialization, and first prediction into trustworthy separate durations.

Core ML and filesystem Instruments recordings were attempted. The exported Core ML interval table had no usable activity rows, so there is **no established cached-load versus prepare-and-cache diagnosis** from Instruments yet.

## Defects already addressed

- **Cleanup XPC boundary:** the helper previously called legacy `complete(prompt:maxTokens:)`, losing the caller's interactive deadline, priority, generated-token count, and truncation flag. It could use a 30-second runtime limit instead of the configured interactive budget. The updated protocol forwards those fields and uses `runtime.completion(...)`; its version is now 4. The native runtime already supports deadline checks. A failing regression reproduced the wrong call before the fix, then passed afterward.
- **Helper residency:** the listener previously created a new runtime/service for each connection. The pending fix shares one service for the helper process lifetime, allowing its existing idempotent model loader to reuse residency across connections. A helper process crash still requires a reload. Packaged reconnection behavior remains UNTESTED.
- **Enhancement compilation:** the dependency compiled `DeepFilterNet3-Streaming.mlpackage` into a temporary directory whenever a new runtime lacked a persistent bundle. The fix publishes `DeepFilterNet3-Streaming.mlmodelc` atomically beside the verified source files, with a model-revision/OS cache marker and shared in-flight compilation. It preserves CPU+GPU and the same weights. The preparation regression took 3.010 s before the fix; five fresh cached test processes took 0.328, 0.101, 0.076, 0.073, and 0.085 s, median **0.085 s**. This is an enhancement-test improvement, not an ASR or whole-app startup speedup.
- **Insertion overhead:** known editable/secure roles no longer request two unnecessary AX attributes; baseline capture skips an unused selection query when no field value is available; verification observes the field before paying a fixed 40 ms polling delay. Existing focus, secure-field, clipboard-restoration, and fallback behavior remains covered by tests. Actual foreground-app insertion latency is UNTESTED.
- **Hotkeys:** physical modifier flags now take precedence over a tracker that can lose an edge during tap resets. Double-tap expiration is checked against event timestamps, and startup guards against duplicate event consumers. Physical Fn/right-Command operation is still UNTESTED on a packaged build.

Passing checks observed: 36 ASR tests; 25 llama.cpp/core-cleaner tests including real-model examples and cancellation; 8 helper tests; 8 enhancement tests including the installed model; 88 insertion tests; 15 hotkey tests; 19 gesture tests; 31 app tests; architecture/forbidden-pattern lint. The app built earlier in this work, before the latest enhancement-cache and helper-lifetime edits. A final integrated build, complete repository verification, packaged XPC behavior, and GUI timing remain pending. Some changes remain uncommitted; this is not a release-completion report.

## Documentation and reference-app differences to resolve

Checked on 2026-11-01: the [FluidAudio multilingual guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/NemotronMultilingual.md), its [0.17.7 version](https://github.com/FluidInference/FluidAudio/blob/v0.17.7/Documentation/ASR/NemotronMultilingual.md), and [official releases](https://github.com/FluidInference/FluidAudio/releases). The guide prefers compiled bundles and recommends CPU+ANE for its documented exports. It separates processing chunk size from architectural lookahead. It describes `[56, 0]` exports, unlike our installed `[42, 13]` metadata. Please resolve that discrepancy against the actual pinned implementation and artifacts before applying benchmark claims. Its no-Hugging-Face-repository statement and some API examples also need checking against installed-source reality.

Apple distinguishes compilation, device specialization, cached model loading, and prediction in [Core ML performance analysis](https://developer.apple.com/documentation/coreml/analyzing-a-core-ml-model-s-performance-in-xcode). Please use that distinction when diagnosing our persistent bundles. [CPU+GPU configuration](https://developer.apple.com/documentation/coreml/mlcomputeunits/cpuandgpu) permits CPU fallback. Do not describe it as a GPU-only guarantee.

The owner's GPU requirement differs from the guide's ANE recommendation. Earlier repository measurements on this M1 at the **1120 ms tier** reported CPU 12.7×, GPU 10.9×, and CPU+ANE 2.8× real time. These historical results are not a current 2240 ms comparison. We need hardware/export-specific advice, not an assumption that the guide's ANE result or newer-Mac throughput transfers to this machine.

Our reference app, Hex, is MIT licensed, copyright Christopher Langton 2026. Its main backend is Rust; its speech path uses `transcribe.cpp`/GGUF, not our FluidAudio/Core ML graph. It retains model state and limits GPU-mode CPU decoder workers, but its reported fast startup is not a measured same-model/same-runtime comparison. Copying its loader cannot automatically eliminate Core ML initialization. Hex's UI, assets, branding, and unrelated features are outside this performance task. Meeting feature ports are waiting for a separate inventory/approval step.

## Questions requiring expert guidance

1. **Feasibility:** Can this exact M1, Core ML export, and runtime load into a fresh process within one second? If not, state the blocking work and the measurements needed to prove it. Distinguish an unsupported promise from a lifecycle fix.
2. **Residency:** Our resident stream acquisition is already below 2 ms. What supported mechanism, if any, preserves the necessary GPU/model state across an app-process restart? Would it require an independently owned service or launch-at-login behavior? Explain the lifecycle and memory costs; do not silently propose another runtime.
3. **Load-path diagnosis:** How do we obtain reliable Core ML load/cache/specialization intervals on this macOS version when the exported interval table is empty? Give exact instrumentation steps and expected signals. How can we separate encoder bundle reads from MPSGraph reconstruction and hardware specialization?
4. **Artifact mismatch:** What does `[42, 13]` imply for this installed 2240 ms export compared with the documented `[56, 0]` builds? Is that expected for our model version? Which metadata, graph inputs, artifact revision, and loader settings must be checked before declaring an error?
5. **Default streaming:** Is the append/process/callback/finish/reset usage described above correct for FluidAudio 0.17.7? What extra configuration is genuinely required to guarantee streaming throughout recording? Can subsecond live partials be achieved with this exact tier and lookahead? If a different export is necessary, identify the approval and accuracy tradeoff explicitly.
6. **GPU configuration:** Which officially supported Core ML settings improve this exact graph's load time and steady-state GPU latency? Should any decoder components use a different compute policy? Show how the pinned public API supports the change. Do not prescribe low-precision accumulation, optimization hints, or environment overrides without accuracy and performance verification.
7. **Safe warm-up:** The vendor already warms individual models. How do we keep initialization and prediction caches hot without another unsafe synthetic streaming pass or repeated compilation? Can supported APIs avoid loading unused component models while retaining the existing decoder behavior?
8. **Stop-to-insert:** Short recordings defer cleanup until the final commit. What is the smallest safe way to overlap useful cleanup with live ASR, if needed, while handling revisable partials and preserving every word? Define when text becomes authoritative and how cancellation/final assembly work.
9. **Contention and deadlines:** Does warming ASR, enhancement, and three cleanup contexts concurrently hurt startup on an 8 GB M1? What should be serialized, overlapped, or retained? Account for worker queue time, per-request deadlines, cleanup retries, and final-segment work rather than only reporting ASR throughput.
10. **Proof:** Specify a minimal experiment matrix for first-ever preparation, fresh-process cached startup, resident recording start, paced first partial, and stop-to-visible-paste. State the timestamps, success checks, quality comparisons, repetitions, and rejection criteria needed to accept a fix.

Please respond with a ranked diagnosis separating evidence from hypotheses, the smallest concrete Swift/API changes, source links and version requirements, and a short experiment that could disprove each recommendation. Identify any missing measurement precisely. We need help removing the remaining wait, not hiding the loading state or claiming a speedup that was not measured.
