# Agent 1 — FeatureIsland rebuild report

## Status
DONE. All work stayed inside `Packages/L3-Features/FeatureIsland/**` plus this report.
No commits, no git writes, no GUI windows opened (all verification headless).

## What was built
- `Tokens.swift` — the single declaration of space, radii, colors, type roles, durations and sizes. New views contain no structural literals.
- `IslandFlow.swift` — pure `enum` state machine + total reducer + `@Observable` store. No AppKit. Covers `collapsed → compose → listening → thinking → answer`, `collapsed → meetingLive → meetingEnded(suggestions) → answer`, any → history / settings / error / permission / undo, plus `.entered`/`.exited` presence variants. `IslandFlowMetrics.swift` maps state → silhouette geometry.
- `IslandShell.swift` — the attached silhouette as one continuous opaque-black `NotchShape` (flat top at screen maxY, rounded bottom, no glass/shadow/border), morphed by the existing `IslandMotion` springs; content is laid out at its destination size and revealed by the shape. Reduce Motion snaps and shows final states.
- Rebuilt views: `FlowContent.swift`, `ComposeAndAnswer.swift`, `MeetingViews.swift`, `PanelViews.swift` — compose, listening (live transcript + reused pixel waveform), thinking, streaming answer with Copy, suggestion chips, meeting live/ended, history, settings with prompt-theme selector, error, permission, undo, collapsed lamp. Bare SF Symbols only.
- Backend and renderer preserved untouched: `IslandModel`, `IslandFeed`/`IslandEvent`, `IslandPhase`, `NotchGeometry`, `NotchShape`, `IslandMotion`, `IslandMeter`/`WaveformModel`, `EdgeFade`, `IslandFX`, `IslandPixels`, and the pixel waveform renderer (`PixelWaveform.swift` is byte-identical to HEAD).
- Intelligence integration without an L3→L3 import: `IntelligenceSeam.swift` (local protocol + fallback host) and `IslandModel.intelligenceContent: ((IslandFlowState) -> AnyView?)?`. The app seam injects hosted content; `IntelligenceContent` is kept as a public typealias so the existing App-side conformance compiles unchanged.

## Coordinator fixes (all closed)
1. **L3→L3 dependency removed.** Deleted `ModuleIntelligenceSeam.swift`; removed the FeatureIntelligence package/product from `FeatureIsland/Package.swift`; added the injected-closure seam on `IslandModel`. `./tools/check-deps` and `make deps-check` both print "Dependency layers are valid." (exit 0). App builds.
2. **Frozen `IdleLampMotionTests.swift` restored** verbatim from `git show HEAD` (full 84-line assertions). Reintroduced the shared `IdleLampView` + `IdleLampMotion` (`IdleLamp.swift`) used by the collapsed state, so the head/Reduce-Motion assertions pass without weakening.
3. **Frozen `IslandSnapshotTests.swift` restored** verbatim from HEAD, including `testLongCancelledTranscriptKeepsUndoInsideTheContentGutter`. Added an `.undo(text:)` flow state and `UndoView` with the accent Undo button inside the content gutter; the frozen pixel-bounds assertion passes. `git diff HEAD` for both frozen test files and `PixelWaveform.swift` is empty.
4. **Waveform regression closed.** `PixelWaveform.swift` restored byte-identical to HEAD (renderer not replaced, not edited). Waveform tests pass: `IslandWaveformWiringTests` 6/6, `WaveformModelTests` 9/9.
5. **Release verification run** (see exact results below).

## Tests — exact results
- `swift test --package-path Packages/L3-Features/FeatureIsland` — **106 tests, 0 failures** (153.2 s), 2026-11-18 10:06.
- `swift test --package-path Packages/L3-Features/FeatureIsland --configuration release` — **106 tests, 0 failures** (147.0 s), 2026-11-18 10:09.
- `./tools/check-deps` → `Dependency layers are valid.` (exit 0).
- `make deps-check` → `Dependency layers are valid.` / `Dependency checker rejects a forbidden L0-to-L1 import.` (exit 0).
- `swift build --package-path App/SuperflowApp` → `Build complete!` (AppCore seam intact).
- New coverage: `IslandFlowTests` 16 tests (every state, both flows, every transition and guard, totality/determinism, entry/exit, hosted seam), `IslandFlowSnapshotTests` 4 tests rendering 13 states at 2× in dark and Reduce Motion with flat-top/bounded-bottom, opaque-black body and Reduce-Motion final-state assertions.
- Two visual review passes over 26 PNG snapshots in `.proof/island/snapshots/` (all states, dark + reduce). Found and fixed a clipped settings row and a clipped listening shelf in pass 1; pass 2 clean.

## Files changed (FeatureIsland only)
Added: `Tokens.swift`, `IslandFlow.swift`, `IslandFlowMetrics.swift`, `IslandShell.swift`, `IslandEnvironment.swift`, `IdleLamp.swift`, `IntelligenceSeam.swift`, `FlowContent.swift`, `ComposeAndAnswer.swift`, `PanelViews.swift`, `MeetingViews.swift`, `Tests/.../IslandFlowTests.swift`, `Tests/.../IslandFlowSnapshotTests.swift`.
Rewritten: `IslandRoot.swift` (same public `init(model:)`, now hosts the new shell).
Edited: `IslandModel.swift` (injection seam only), `Package.swift` (no intelligence dependency after fix), `IslandMotion.swift`/`IslandPixels.swift`/`islandFX.swift` (reduce-motion environment key).
Deleted the old view files (`IslandStage`, `IslandWings`, `IslandCard`, `IslandIdle`, `IslandHistory`, `IslandAssistantCard`, `IslandMeetingPanel`, `IslandNoticeCard`, `IslandPasteFailed`, `IslandMarks`, `IslandLiveLine`, `IslandMeetingDiscard`, `IslandTransitions`).
Restored byte-identical: `PixelWaveform.swift`, `IdleLampMotionTests.swift`, `IslandSnapshotTests.swift`.
Largest owned file is 386 lines (< 400).

## Unresolved / handoff
- The App side must set `islandModel.intelligenceContent = { state in … }` (using its `IntelligenceIslandSeam.content(for:)` / `AppCoordinator.intelligenceContent(for:)`) to display Agent 4's real Intelligence views in compose/answer. That wiring lives in `App/SuperflowApp/**`, outside my ownership; until it is set, the local `LocalIntelligenceSeam` renders compose/answer honestly with no network work.
- Suggestions for `meetingEnded` are supplied by the Intelligence backend through that seam; the Island carries whatever array it is given and invents none.
