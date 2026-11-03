# ASR Runtime Toggle

## Goal
Persist a runtime choice and route live ASR through either FluidAudio/Core ML or sherpa-onnx. Default new installs to sherpa-onnx with Nemotron 3.5 Streaming.

## Non-goals
Support Granite GGUF, add an ASR daemon, or change the active runtime during a recording.

## Invariants
- Missing runtime settings decode to sherpa-onnx; saved legacy profile choices remain intact.
- One sherpa recognizer owns the shared model; each audio source gets its own stream.
- Runtime changes apply on next launch; current streams remain bound to their recognizer.
- Model downloads are pinned, integrity-checked, staged, and only installed when complete.
- Sherpa supports only Nemotron 3.5; FluidAudio keeps its existing streaming profiles.

## Failure modes
- Missing or corrupt model: runtime is unavailable; record-time warm-up fails clearly and never downloads.
- Failed/interrupted download or extraction: staged files are discarded; no partial model is available.
- Unsupported profile for selected runtime: settings normalize to Nemotron 3.5 for sherpa.
- sherpa recognizer creation failure: prepare fails and the selected runtime remains unavailable.

## Approach
Add the runtime enum to Kernel settings, a sherpa adapter using the official pinned SPM package and pinned 80 ms model archive, and a launch-selected router at app composition. Expose separate runtime-specific model providers to Settings and a quiet runtime picker with a restart note.

Sherpa requests ONNX Runtime's Core ML provider by default. Upstream exposes no strict GPU-only mode; Core ML can schedule supported work across Apple compute units and fall back for unsupported operations.

## Steps
1. Add runtime setting and compatibility defaults. Verify Kernel settings tests.
2. Add Sherpa package, verified model installer, shared recognizer, and stream adapter. Verify package tests/build.
3. Add router and runtime-specific Settings providers; select persisted runtime before prewarm. Verify app tests/build.
4. Add Settings picker and restart status. Verify feature tests and app build.
5. Review changed diff and preserve unrelated worktree edits.

## Files
Kernel Settings; ASRSherpaOnnx package; app package/environment/coordinator; FeatureSettings view model and Dictation tab; runtime tests; third-party notices.

## Scope note
This adds the requested second runtime despite the existing latency plan's no-new-runtime boundary; no daemon or additional model tier is introduced.
