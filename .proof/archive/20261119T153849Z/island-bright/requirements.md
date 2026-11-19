# Agent 3 — Island Bright / Blue / Sharp / Smooth

Owner scope only: `Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland/{PixelTheme,Tokens,IslandMotion,IslandShell,ComposeAndAnswer,FlowContent,MeetingViews,PanelViews,IntelligenceSeam,islandFX,IslandPixels,IdleLamp,IslandMeter,PixelWaveform}.swift`, FeatureIsland tests (add only), `.proof/island-bright/**`.

1. COLOUR — raise the pixel ramp to vivid superflow blue; keep one accent (blue 600) and the opaque-black body; no gradient/shadow/stroke; meter/signal/readout lines crisp and visible at 2× dark.
2. SHARPNESS — every cell/frame on the 1/scale grid via IslandPixelGrid/Pixel.snap; no half pixels; 4 pt alignment; remove no-information elements; two screenshot review passes per DESIGN_RULES.
3. MOTION — existing spring engine, no jank; profile with a DEBUG FrameProbe; ~60 FPS, no long frames; fix per-frame allocations; Reduce Motion end states; no decorative loops.
4. PRESERVE — exhaustive state machine, accessibility labels, all snapshots, 106+/106 tests.
5. VERIFY — swift test FeatureIsland debug + release; tools/lint-forbidden clean; swift build App/SuperflowApp release green; 2 headless screenshot passes via ISLAND_SNAPSHOT_DIR; LOOK at PNGs; document before/after.
6. DELIVER — `.proof/island-bright/report.md` with exact changes, before/after screenshots, measured frame numbers, test/lint/build evidence, honest UNVERIFIED items. STATUS DONE only if all pass.
