# Short transcript latency and Intelligence trigger

## Root causes
- The Intelligence trigger is saved only in `@AppStorage`; no hotkey source reads it or routes it to the Intelligence page.
- Short S1-mini cleanup is not the measured bottleneck: direct release runs on GPU took a 164 ms median for the two-second fixture. A two-second ASR fixture on the 2240 ms tier produced its first partial after the clip ended.
- Product metadata selects the Nemotron 1120 ms tier, while the adapter loads 2240 ms. A run against 1120 ms on the current worktree produced its first partial at 12.9 s, so the tier change alone is not yet a proven speedup.
- DeepFilterNet output had no post-model gain; the raw microphone journal is independent from this enhanced inference path.

## Changes
- Align the adapter with the product's 1120 ms model tier; keep the measured cold first-partial result visible rather than claiming a speedup.
- Apply 1.32× gain to enhanced samples with a 0.98 peak ceiling, preserving the raw journal and model-failure passthrough.
- Carry the configured physical trigger through the event tap to `MainWindowController.show(.intelligence)`.
- Offer left/right Option alongside left/right Control trigger choices; the selected trigger routes before dictation gestures.
- Add focused mapper and routing coverage; track both confirmed issues in `issue.md`.

## Verification
- Before: release live-model short cleanup timings and first-partial timings.
- After: HotkeyEngine tests, app coordinator routing, enhancer gain bounds, ASR catalog mapping, and inspect the final diff.
- Do not report a speedup unless repeated real-model runs show one.

## Results
- S1-mini cleanup: two-second input median 164 ms across five warmed GPU runs.
- Same-code ASR comparison on a two-second clip: 2240 ms first partial at 2400 ms (after the 2136 ms input end); 1120 ms first partial at 1309 ms (before the 2319 ms input end), one commit and no failures.
- The first isolated 1120 ms run took 12873 ms to first partial. A repeated run took 1309 ms, so this change improves the warmed path but does not remove the first-run cost.
- 1120 ms ten-second clip: first partial at 1184 ms, nine partials, one commit, no failures, 0.87x real-time factor.
- HotkeyEngine (20 tests), ASRFluidAudio (36), FeatureSettings (27), EnhancementDeepFilterNet (9, with two opt-in real-model tests skipped), and the app route test passed.
