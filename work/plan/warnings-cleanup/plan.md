# Plan: Clear actionable build warnings

## Root cause
Four source-level warnings remain after the helper build fix: a deprecated Keychain constant, an ignored `try?` result, an unused sorted binding, and a redundant `[weak self]` capture. The C++17 warnings originate in the third-party `mlx-swift` checkout and are not ours to change.

## Invariants
- Reflection keychain behavior is unchanged: no system prompt on existence/load; auth-blocked items still count as saved.
- No text/audio logging, no behavioral changes in text resolution or launch prep.

## Files and changes
- `Packages/L2-Engines/MeetingIntelligence/.../ReflectionCredentials.swift`: import `LocalAuthentication`; replace `kSecUseAuthenticationUIFail` with `query[kSecUseAuthenticationContext] = LAContext()` configured with `interactionNotAllowed = true` in `exists()` and `load()`.
- `Packages/L1-Adapters/ModelStore/.../RangedTransfer.swift`: assign `try? handle?.seekToEnd()` to `_`.
- `Packages/L2-Engines/TextPipeline/.../AIEraResolver.swift`: remove unused `variants` binding; move its longest-first rationale onto the existing span loop.
- `App/SuperflowApp/Sources/SuperflowAppCore/AppCoordinator+Launch.swift`: drop unused `[weak self]` and `guard let self` in `startModelPreparation`.

## Verification
- Focused package builds/tests covering the four files, with warning grep clean for each.
- `swift build --package-path App/SuperflowApp --configuration release` warning-grep clean for our sources.
- `tools/test-buildfix`, then `make buildfix` end-to-end packaging.
