# Open questions

- Bundle and register the Exposure Italic font specified by `DESIGN.md`. Display text currently uses the serif fallback because no font asset is present.
- Define a shared content-width token for the 900 pt Settings, Shortcuts and Dictionary columns; `DESIGN.md` does not specify one.
- Define the contribution-cell radius token; the current 2 pt value is local to `ContributionGrid`.
- Confirm the `StatTile` value type role. It uses `Typography.title` because `DESIGN.md` does not define a stat or number role.
- Verify light and dark appearances, focus rings, VoiceOver labels, Reduce Motion/Transparency, resizing, pointer cursors, and Island drag and position persistence in the running app.
- Validate Core Audio process tap and ScreenCaptureKit fallback with Zoom and Meet. Both paths are implemented; device behavior remains unverified.
- Run a real meeting with FluidAudio Sortformer and verify diarization accuracy, speaker changes, echo handling, and export quality. The adapter is linked and wired into `AppEnvironment`; device acceptance remains unverified.
- The symbol conflict between `PLAN.md` §18.2 and `DESIGN.md` is resolved in [ADR 0011](adr/0011-native-system-symbols.md): app UI follows `DESIGN.md` and renders hierarchical SF Symbols.
- The Island shadow conflict is resolved in favor of `DESIGN.md`; the panel remains shadow-free.
