# Plan: Stop the Core ML startup abort

## Root cause
The latest report aborts on Core ML's async prediction queue. Launch runs ASR/VAD preparation while DeepFilterNet performs ten synthetic Core ML predictions, creating needless overlapping inference.

## Files
- `Packages/L1-Adapters/EnhancementDeepFilterNet/Sources/SuperflowEnhancementDeepFilterNet/DeepFilterNetEnhancer.swift`
- `Packages/L2-Engines/SessionEngine/Sources/SuperflowSessionEngine/SessionEngine+Lifecycle.swift`
- `App/SuperflowApp/Sources/SuperflowAppCore/AppCoordinator+Launch.swift`
- `App/SuperflowApp/Sources/SuperflowAppCore/AppCoordinator.swift`
- `issue.md`

## Changes
1. Remove the ten zero-audio DeepFilterNet predictions; keep model load and state reset.
2. Remove the session engine's detached enhancement warm-up so launch has one owner for model preparation.
3. Start the Models view's enhancement preparation only after ASR/VAD warm-up completes.
4. Record the latest incident and leave it unresolved unless launch and real dictation are verified.

## Verification
- Build and package the current app.
- Open the packaged app and confirm the process stays alive past the previous 28-second failure window.
- Real dictation is not verified in this turn.
