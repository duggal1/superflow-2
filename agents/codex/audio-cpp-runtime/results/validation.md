# audio.cpp migration validation

- Source pin: 06c13737cc39481787a03465697b58b1c954b56f, cloned under ThirdParty/audio.cpp.
- Release arm64 C ABI built for macOS 15 with Metal and embedded shaders; selected Nemotron ASR and diarization.
- ASR and diarization GGUF downloads verified against pinned SHA-256 values in AudioCppAsset.swift.
- Forced streaming sessions and explicit Metal backend; Q8 weights; two bounded resident session slots.
- Native golden passed: complete transcript, partial events, flush, idempotent finish, warm reuse, pause resets, nonzero timestamps, canonical speaker IDs.
- Latest warm sample: 7.435 seconds of public speech in 2.991 seconds, one run on a busy M1; includes stream start, inference and final flush. No before/after speed claim.
- KernelSupportTests: 15 passed. ModelsViewTests and SettingsViewModelTests: 23 passed. RecoveryTests: 9 passed.
- Recovery data-loss regression failed before the fix and passed afterward; failed sources retain both meeting journals.
- App built, packaged and signature verified. Packaged executable loads its bundled libaudiocpp.0.dylib; developer build rpath removed.
- FluidAudio packages and dedicated app/repository model caches removed. Historical ASR descriptors removed; CLI and stored-profile fallbacks use the supported default.
- Dependency gate is blocked by two pre-existing violations in the untracked ASRSherpaOnnx adapter, which imports L1 ModelStore.
- No full release gate or real microphone/paste/long-session test was run. Shared files contain pre-existing unrelated edits; no mixed commit was made.
