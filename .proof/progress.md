# Plan

Goal: revert the Notch/Island front end and Intelligence page to the last good pre-rewrite state (`c5110df`), keep the backend, fix the dictation output path, raise transcription quality, restore the normal (non-pixelated) icon, then delete + rebuild + install + open the app.

Baseline: `c5110df` (2026-11-10) is the last commit before `011e114` / `61ec24a` (2026-11-17) rewrote the Island and Intelligence surfaces. `FeatureIntelligence` did not exist before `c5110df`; `FeatureIsland` had a complete older implementation.

Non-goals: no change to ClearlyInput/ClearlyStealth adapters or MeetingIntelligence engine; no redesign of the Knowledge page; no removal of backend quality work (cleanup, audio, storage, recovery).

Invariants:
- The transcription pipeline and its quality tests stay green.
- No secrets, no force-push, no reset/restore of unrelated work.
- Uncommitted compile fixes from the previous task are preserved.

Steps:
1. Revert `FeatureIsland` sources+tests to `c5110df`; remove files added after it.
2. Remove `FeatureIntelligence` package; revert its consumers (AppEnvironment, App Package.swift, IntelligenceTab, SettingsValidation, FeatureSettings tests).
3. Revert island host wiring: `main.swift`, `AppCoordinator+Input`, `AppCoordinator+IntelligenceIsland` (delete), `IntelligenceIslandSeam` (delete), `IslandBridge`, `IslandPanelController`, `AppCoordinator+Launch`, `AppEnvironment`.
4. Revert island/intelligence tests added by the rewrite; restore `WarmupGestureTests`.
5. Restore `brand-mark.svg`, AppIcon PNGs, remove pixelated favicons.
6. Build; fix every compile error at the root cause.
7. Run package + app tests, quality tests, headless Island snapshot driver.
8. Investigate the "history has data but no output" backend failure; fix the paste/output path.
9. Raise transcription quality where the quality harness shows failures.
10. Delete stale app bundle, rebuild release, sign, install to /Applications, open.
11. Completion audit (two passes) + independent review.

Progress:
- Task started; previous proof archived to `.proof/archive/20261124T175500Z/`.
