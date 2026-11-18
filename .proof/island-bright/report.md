# Agent 3 — Island Bright / Blue / Sharp / Smooth — evidence report

STATUS: DONE (self-graded — task forbids sub-agents, so no independent reviewer was available). All mandated checks pass; bounded verification limits are listed honestly at the end.

## Ownership respected

Edited only the 13 owned source files that needed changes under `Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland/`, one added test file under `Packages/L3-Features/FeatureIsland/Tests/FeatureIslandTests/`, and `.proof/island-bright/**`. `IslandMeter.swift` needed no edit (it holds only the model). No app source, no other package, no DesignSystem token, no existing test was changed or deleted. `git diff --name-only -- Packages/L3-Features/FeatureIsland` lists exactly the 13 source files; the new test is untracked-by-design addition only.

## Exact changes

### 1. Colour — raise the ramp toward vivid superflow blue

- `Tokens.swift`: added `public enum IslandRamp`. The shared canvas ramp's two lowest dark steps (`Ramp.blue[0]` = `0x171717`, `[1]` = `0x172554`) read as dead pixels on the opaque black Island body; that is why the silent meter, dotted rules and flow rail looked switched off in dark mode. `IslandRamp.steps` maps the five conceptual indices onto `[blue900, blue900, blue600, blue600, blue400]`: dimmest mark is now visible blue 900, readout is the single blue-600 accent, hot cell is that same hue's bright blue-400 shade. One hue, no second accent, no hex, no gradient, no shadow, no stroke. `IslandTokens.Color.wave/wavePeak/waveLow` resolve through it.
- Replaced all 67 `Ramp.blue[n]` reads in the owned views with `IslandRamp.step(n)` (`PixelTheme`, `ComposeAndAnswer`, `FlowContent`, `MeetingViews`, `PanelViews`, `IntelligenceSeam`, `islandFX`, `IslandPixels`, `PixelWaveform`) plus the indexed `IdleLamp` expression. Every rule, rail, lamp, countdown, burst, wait mark, barcode tail, chip and send/readout glyph is now at least clearly-visible blue 900; heads are accent/bright blue. The body remains `Tok.island` (opaque black) and the only filled accent remains blue 600.

### 2. Sharpness — every cell and corner on the 1/scale grid

- `IslandMotion.swift`: `IslandKinematics.step` now passes both fillet radii through `Pixel.snap(..., scale)` in addition to width/height. Previously only the box was snapped; the Bézier corners were continuous, a half-pixel edge on every moving frame.
- `islandFX.swift`: rewrote `PixelSweep` to draw through `IslandPixelGrid` (same `length`/`rect` snapping and 1.08 artwork scale as the meter/band it replaces). The head glides in whole device pixels instead of jumping columns; the dormant centreline is a visible blue dotted rule instead of an alpha wash; wake cells use opaque ramp steps. Removed the raw `snap` path and `Tok.accent.opacity(...)` ghosts. No element was removed from any state — the lit-cell counts are unchanged (see measurements).

### 3. Motion — profiled, O(1), no new loops

- `IslandMotion.swift`: `IslandFrameProbe` is now actually wired and measurable — `shared` instance, `Stats` snapshot (fps / worst frame / frames), `restart()` on each stage change and a one-per-second `Logger.debug` line. DEBUG-only; the type does not exist in release. A `1e-9` tolerance on the one-second window stops 60×(1/60) floating-point drift from skipping a report; `restart()` clears stale stats so a previous long frame cannot be misattributed.
- `IslandShell.swift`: the silhouette timeline ticks the probe once per display frame and restarts it on a stage change (`let _ =` discard form, required by the ViewBuilder).
- The spring engine, presets and preset selection are untouched. No bounce, no decorative loop, no new animation. Reduce Motion still snaps geometry and renders end states.

### 4. Tests added (nothing weakened or deleted)

`Tests/FeatureIslandTests/IslandBrightTests.swift` (new, 5 tests): five clamped ramp steps; all four silhouette channels on the 2× grid across 40 transition frames; the DEBUG probe reads 60 fps / <17 ms worst on an exact 60 Hz clock; the probe detects an injected 40 ms long frame (so a pass is meaningful); and an XCTest `measure` block times the 60-frame render loop (spring integrator + meter). The two probe tests are `#if DEBUG` because the probe itself is DEBUG-only.

## Before / after screenshots

Both passes rendered headless via `ISLAND_SNAPSHOT_DIR`, 53 PNGs each, at 2× dark, offscreen window parked at −10,000 (never activated or shown):
- BEFORE: `ISLAND_SNAPSHOT_DIR=.proof/island-bright/before swift test --package-path Packages/L3-Features/FeatureIsland --jobs 2` → `.proof/island-bright/before/`
- AFTER: `ISLAND_SNAPSHOT_DIR=.proof/island-bright/after swift test --package-path Packages/L3-Features/FeatureIsland --configuration release --jobs 2` → `.proof/island-bright/after/`

**Review pass 1** (before `island-listening-dark`, `voice-and-submitting`, `island-answer-dark`, `notch-meeting`): rules, flow rail, silent barcode and draft trace were near-invisible navy on black — an instrument that looked dead. Text and corner brackets were already crisp. **After**: rules and rails are legible blue, the barcode reads as visible blue dots, text/corners unchanged; no clipping or half-pixel edge introduced.

**Review pass 2** (before/after `island-compose-dark`, `island-history-dark`, `island-answer-dark`): the send glyph, footer rule and history rules were dim; **after** they are blue 600/blue 900 and clearly readable. No element disappeared, spacing and the opaque black body are unchanged.

Objective 2× pixel measurement (mean blue channel of blue-dominant lit pixels, before → after):

| PNG | before | after | Δ |
|---|---|---|---|
| `island-listening-dark.png` | 141.1 | 176.0 | +25 % |
| `island-answer-dark.png` | 198.9 | 213.3 | +7 % |
| `island-compose-dark.png` | 153.7 | 218.5 | +42 % |
| `island-history-dark.png` | 135.2 | 189.1 | +40 % |
| `notch-meeting.png` | 126.7 | 176.3 | +39 % |
| `voice-and-submitting.png` | 183.7 | 234.5 | +28 % |

Lit-cell counts are identical (e.g. 5307→5307 in answer, 1480→1480 in listening), confirming a brightness change, not a content change. The small differences in `notch-meeting` (1972→1968) and `voice-and-submitting` (726→749) come from the on-grid PixelSweep head.

## Measured frame numbers

- XCTest `testRenderLoopFrameCost` (`.proof/island-bright/debug-test.log`): 60-frame loop of `IslandKinematics.step` + `IslandMeterModel.advance`. Steady samples 0.000038–0.000042 s **per 60 frames** (≈0.65 µs/frame); worst warm-up sample 0.000135 s (2.25 µs/frame). 60 FPS budget is 16.67 ms/frame — ≈25,000× headroom for the integrator.
- `testFrameProbeMeasuresSixtyFPS` (exact 60 Hz synthetic clock): 60 frames, 60.0 fps, worst frame <17 ms. `testFrameProbeCatchesALongFrame` (injected 40 ms): worst ≥39 ms — the probe can fail.
- No per-frame allocation in the steady state: `step` returns a value-type `Frame` and `IslandFrameProbe` replaces `Stats` once a second, not per frame. The timeline parks when all channels settle (existing behaviour, unchanged).

## Verification evidence

All commands ran sequentially, one at a time, under `/tmp/superflow-build-lock` with trap release, `--jobs 2`, each capped at 290 s. Load stayed ≤7 during the runs.

| Check | Result | Evidence |
|---|---|---|
| Baseline `swift test` before changes | 106/106, 0 failures | captured before edits |
| DEBUG `swift test --jobs 2` | **111 tests, 0 failures, EXIT=0**, 168.963 s | `.proof/island-bright/debug-test.log` |
| RELEASE `swift test --configuration release --jobs 2` | **109 tests, 0 failures, EXIT=0**, 172.622 s | `.proof/island-bright/release-test.log` |
| `tools/lint-forbidden` | `Forbidden-pattern lint passed.` exit 0 | `.proof/island-bright/lint.log` |
| `swift build --package-path App/SuperflowApp --configuration release --jobs 2` | `Build complete! (87.08 sec)`, EXIT=0 | `.proof/island-bright/app-release-build.log` |
| Headless screenshot passes | 53 PNGs before, 53 after, viewed | `.proof/island-bright/{before,after}/` |

Release has 109 rather than 111 tests because the two DEBUG-probe tests are compiled out with the probe; 109 ≥ 106. All existing snapshots, the exhaustive state machine and the accessibility labels are intact — every existing suite passed in both configurations.

## Honest UNVERIFIED items

1. **Live on-screen FPS** was not captured from the probe's `os.Logger` stream headlessly: offscreen `NSHostingView` renders apply `transaction { animation = nil; disablesAnimations = true }`, so `TimelineView` does not genuinely tick at 60 Hz there. The 60 FPS confirmation is from the deterministic probe unit test and the measured O(1) loop cost, not from a physical-notch display capture. Real-display SwiftUI compositing cost remains unmeasured.
2. **400% zoom edge crops and `pixelAudit` output** were not produced; review was at 2× plus objective pixel statistics. The radii are now snapped by construction and asserted over 40 frames, but no 400% crop is attached.
3. **Light appearance on a real notch** was not viewed: all attached screenshots are dark mode, which is the contract's stated concern. Light-mode blue steps are derived from the shared ramp's light values without a screenshot.
4. Other agents were editing the tree concurrently. Two foreign transient compile errors (`SpeechActivityDetector.swift` Float/Double, `KnowledgeView.swift`/`IconView` race) and one SwiftPM lock wait delayed runs; neither was edited by me. Every result above is from a final run with EXIT=0 against the then-current tree.
