# Performance + Intelligence fix plan
## Root causes
- Cleanup capped at 2 workers + 2 llama contexts; long text queues behind them.
- ASR prime creates session without feeding audio; Metal compiles on first dictation (16s).
- Intelligence .task calls SecItemCopyMatching on MainActor with auth UI enabled; blocks UI and shows login prompt.
- Intelligence trigger defaults to leftControl; user expects rightOption; nav blocked by Keychain.

## Changes
- CleanupConfig/CleanupService/SessionCleanupCoordinator/LlamaCppRuntime: raise cap 2->6, default 6. Keep 250/850 chunking.
- AudioCppRuntime.prime: feed 24k silence + finish after start to compile kernels (Hex load pattern).
- AppCoordinator+Launch: after ASR prewarm, prewarm S1-mini (serial, utility) instead of lazy.
- ReflectionCredentials: kSecUseAuthenticationUI=Fail on load/save; add exists() without data.
- IntelligenceTab: load exists off MainActor via Task.detached; never prompt on appear.
- Intelligence trigger default leftControl->rightOption (IntelligenceTab + AppCoordinator fallback).
- Streaming already mandatory (audio.cpp "streaming"); no change, verify.

## Verify
- TextCleanup + LLMLlamaCpp + AudioCpp + HotkeyEngine + AppCore tests.
- ColdPreparation timings; Intelligence nav without prompt; single-press routing.
