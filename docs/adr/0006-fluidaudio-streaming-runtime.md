# ADR 0006: FluidAudio streaming runtime and ASR model lifecycle

Status: Accepted

## Context

The app's ASR adapter was not linked to FluidAudio. Its conditional bridge called an API that does not exist in the pinned FluidAudio source, and ASR downloads were routed through `ModelStore`, which expects one manifest-described file. FluidAudio EOU is a multi-file Core ML model managed by FluidAudio's model cache.

## Decision

- Pin the `FluidAudio` Swift package to 0.17.7 and use `StreamingModelVariant.parakeetEou320ms`.
- Keep ASR model lifecycle behind the L0 `ASRModelProvider` port. `SpeechRecognizer` extends that port; the L5 composition root supplies the concrete recognizer to onboarding and settings.
- Store FluidAudio-managed ASR artifacts under the app's Application Support directory. Use FluidAudio's model loader and progress callback so its cache recovery and revision handling remain authoritative.
- Lease one EOU manager per active recognition stream. Reuse reset managers after a stream finishes. Split utterances on FluidAudio's EOU callback, flush and reset the decoder at each boundary, and emit bounded recognition events.
- Keep the registry NVIDIA-only. Streaming profiles are selectable; TDT remains visible as batch-only and cannot be selected because FluidAudio's `StreamingAsrManager` does not support its sliding-window pipeline. Adapt `StreamingNemotronMultilingualAsrManager` behind the same protocol for Nemotron 3.5.

## Usage sketch

```swift
let recognizer = FluidAudioRecognizer(modelCacheRoot: supportDirectory.appending(path: "Models/FluidAudio"))
try await recognizer.prepare(profileID: settings.asrProfile) { progress in
    progressReporter.send(progress)
}
let stream = try await recognizer.makeStream(profile: settings.asrProfile, source: .mic)
await stream.feed(chunk)
```

## Current catalog

| Profile | Upstream NVIDIA model | FluidAudio Core ML build | Format |
| --- | --- | --- | --- |
| Parakeet Realtime EOU 120M | `nvidia/parakeet_realtime_eou_120m-v1` | `parakeet-realtime-eou-120m-coreml/320ms` | Streaming |
| Nemotron Speech Streaming 0.6B | `nvidia/nemotron-speech-streaming-en-0.6b` | `nemotron-speech-streaming-en-0.6b-coreml/560ms` | Streaming |
| Parakeet Unified 0.6B | `nvidia/parakeet-unified-en-0.6b` | `parakeet-unified-en-0.6b-coreml` | Streaming |
| Nemotron 3.5 ASR Streaming 0.6B | `nvidia/nemotron-3.5-asr-streaming-0.6b` | `Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML/latin/1120ms` | Streaming |
| Parakeet TDT 0.6B v3 | `nvidia/parakeet-tdt-0.6b-v3` | `parakeet-tdt-0.6b-v3-coreml` | Batch only |

All FluidAudio repositories are under the `FluidInference` organization.

## Alternatives considered

1. Keep `ModelStore` as the ASR downloader and adapt the EOU manager to one model URL. Rejected because the manager requires an encoder, decoder, joint model, vocabulary, and FluidAudio cache revision management.
2. Keep the conditional bridge and add only a package dependency. Rejected because the guarded methods do not match FluidAudio's public API and would still leave recognition unavailable.

## Consequences and limits

This makes the ASR package and app composition statically wired to a real FluidAudio API. FluidAudio downloads and revision-checks its model files, but the plan's separate app-owned SHA-256 manifest is still outstanding. Streaming behavior, model performance, and hardware support remain unverified until builds, tests, and on-device runs are authorized.

## Evidence

Validated against FluidAudio tag `v0.17.7`, commit `503b4bd1bbf7220882de39fe8ae6716aae4132da`: `StreamingModelVariant`, `StreamingAsrManager`, `StreamingEouAsrManager`, `ModelHub`, `ModelNames.ParakeetEOU`, and `Repo.folderName`.
