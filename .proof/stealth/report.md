# Agent 3 — Clearly stealth implementation report

Date: 2026-11-17. macOS 27.2, build 26B123. Scope: keep the Island visible to
the user but not visible to the receiver in a Google Meet / Zoom / Teams share,
using ONLY the public `NSWindow.sharingType = .none` mechanism, enforced on
every app-owned window. No private APIs, no Accessibility permission, no claims
stronger than verified. All verification headless; no GUI window was opened on
the user's screen.

## What I built

### App wiring (file I own)
- `App/SuperflowApp/Sources/SuperflowAppCore/Windowing/IslandPanelController.swift`
  - `IslandPanel.init()` sets `sharingType = .none` BEFORE the first
    `orderFront`, plus empty `title` and `isExcludedFromWindowsMenu = true`.
  - Added a self-contained `WindowGuard` (`enforceStealth()`): re-applies
    `.none` to every window in `NSApp.windows` on `NSWindow.didUpdateNotification`,
    screen-parameter change, active-space change, wake, every Island show /
    re-seat (`place`) and every phase transition. Idempotent. DEBUG assertion
    traps if any app window is capturable after enforcement.
  - Self-contained on purpose: the app builds and is protected without a new
    package dependency (App/Package.swift is not in my ownership).

### New standalone package `Packages/L1-Adapters/ClearlyStealth/**`
- Product `ClearlyStealth` with two targets:
  - `ClearlyStealthCore` (pure Swift, no AppKit): `StealthSharingMode`,
    `StealthStatus` / `UnverifiedReason` / `ProbeMeasurement` /
    `StealthStatusRecord` / `StealthStatusStore` (+ in-memory and UserDefaults
    stores) / `StealthCopy` (bounded, honest UI strings),
    `VerifierClassifier` + `ProbeCapturing` + `VerificationOutcome`,
    `StealthVerifier` (capture → classify → persist per macOS build),
    `WindowGuardCore` (event-driven, injectable, DEBUG-assertable),
    `ScreenCaptureExclusion` (Island/own-window exclusion rule for the OCR
    content filter).
  - `ClearlyStealth` (AppKit + ScreenCaptureKit adapter):
    `StealthWindowController.configureIslandPanel` (`.none` before orderFront,
    level + collection behavior), `AppWindowGuard` (real notification
    observers over `NSApp.windows`), `SCKitProbeCapture` (real magenta
    positive-control / `.none` probe + `SCScreenshotManager` capture, no
    exclusions, ratio test), `StealthSystem` (facade: build string, display
    config, verifier factory, status copy).
- Headless tests: 25 in `ClearlyStealthCoreTests` + 2 in `ClearlyStealthTests`.
  Covers classifier branches (Verified/Failed/Unverified, the anti-false-positive
  positive-control guard, boundaries, out-of-range), verifier with INJECTED
  capture results (pass, forced `.readOnly` → Failed, blocked capture →
  Unverified, stale build, re-verify overwrite), per-build persistence, honest
  copy (no "undetectable"/"invisible to everything"), OCR self-exclusion,
  and WindowGuard enforcement/idempotence/assertion on all events.

### Debug tool `tools/stealth-debug/**`
- `main.swift`: `CGWindowListCopyWindowInfo([.optionAll])` filtered by PID;
  prints window number, name, bounds, layer and `kCGWindowSharingState`
  (table or `--json`); exit 1 on ANY window with sharing state != none (a
  leak), 0 if clean, 2 on bad args.
- `fixtures/probe_windows.swift`: headless fixture creating two OFFSCREEN
  windows (`.none` and `.readOnly`), never ordered front.
- `test.sh`: compiles tool + fixture once, asserts the tool reports exactly one
  leak for the fixture and zero for a clean PID, both in text and JSON mode.
- `tools/README.md` created (was absent) with the tool's docs.

### Docs
- `docs/stealth-compatibility.md`: skeleton matrix, every Meet/Zoom/Teams
  share mode marked UNVERIFIED (no second device), residual leak surfaces,
  explicit statement that the OS respecting the flag is NOT claimed, fill-in
  procedure and bounded copy rules.

## Exact commands run and results

1. `swift test --package-path Packages/L1-Adapters/ClearlyStealth`
   - EXIT 0. `ClearlyStealthCoreTests`: 25 tests, 0 failures.
     `ClearlyStealthTests/AdapterMappingTests`: 2 tests, 0 failures.
2. `zsh tools/stealth-debug/test.sh`
   - EXIT 0. Output: `stealth-debug: leak detected (state 1), .none recognized
     (state 0), clean PID ok` / `PASS: stealth-debug headless self-test`.
3. Isolated typecheck of my edited app file against minimal stubs
   (`swift build` in a temp SwiftPM harness symlinking
   `IslandPanelController.swift`, stubbing `SuperflowFeatureIsland` /
   `SuperflowUIComponents`):
   - EXIT 0, `Build complete!`. Confirms my windowing edits compile.
4. Offscreen window probe (`swift probe_win.swift`, temp):
   - Confirmed an unordered NSWindow appears in `CGWindowListCopyWindowInfo`
     with its real sharing state (`.none`→0, `.readOnly`→1), which is the basis
     of the debug tool.
5. `python3 tools/verify-island` (the repo's full Island harness):
   - EXIT 1, but the errors are in ANOTHER agent's in-progress files
     (`Packages/L3-Features/FeatureIsland/.../IntelligenceSeam.swift`:
     `IslandTokens.Type has no member body/caption`), not in my file. My file's
     isolated typecheck (item 3) passed. Not my scope to fix.

## Files changed (all within my exclusive ownership)
- `App/SuperflowApp/Sources/SuperflowAppCore/Windowing/IslandPanelController.swift` (modified)
- `Packages/L1-Adapters/ClearlyStealth/Package.swift` (new)
- `Packages/L1-Adapters/ClearlyStealth/Sources/ClearlyStealthCore/{StealthSharingMode,StealthStatus,VerifierClassifier,StealthVerifier,WindowGuardCore,ScreenCaptureExclusion}.swift` (new)
- `Packages/L1-Adapters/ClearlyStealth/Sources/ClearlyStealth/{StealthWindowController,AppWindowGuard,SCKitProbeCapture,StealthSystem}.swift` (new)
- `Packages/L1-Adapters/ClearlyStealth/Tests/ClearlyStealthCoreTests/{VerifierClassifier,StealthVerifier,WindowGuardCore,StealthStatusAndExclusion}Tests.swift` (new)
- `Packages/L1-Adapters/ClearlyStealth/Tests/ClearlyStealthTests/AdapterMappingTests.swift` (new)
- `tools/stealth-debug/{main.swift,test.sh,fixtures/probe_windows.swift}` (new)
- `tools/README.md` (new)
- `docs/stealth-compatibility.md` (new)
- `.proof/stealth/report.md` (this file)

No git writes were made. `.proof/requirements.md` and `.proof/progress.md` were
not touched.

## Unresolved / UNVERIFIED

- **OS respects the flag: NOT CLAIMED.** Apple labels `sharingType` legacy and
  does not promise ScreenCaptureKit honors it; third-party evidence is
  contradictory across macOS builds. The app applies the flag and enforces it;
  whether a given client hides the Island is decided by the real share test.
- **Real capture verification (`StealthVerifier` runtime): UNVERIFIED.** The
  capture path needs Screen Recording permission and briefly shows probe
  rectangles on screen, which violates the headless-only constraint for this
  task. Logic and persistence are tested with injected captures; the real
  `SCKitProbeCapture` was compiled but not executed.
- **Share-mode matrix: UNVERIFIED.** No second device was available. All
  Meet/Zoom/Teams Entire Screen/Window/Tab cells are marked UNVERIFIED in
  `docs/stealth-compatibility.md`.
- **App target integration of the package:** `App/Package.swift` (not my file)
  does not yet declare a `ClearlyStealth` dependency, so the verifier/status UI
  is not wired into the running app. The core hiding behavior IS wired
  self-contained in `IslandPanelController.swift`. The integrating agent needs
  to add the package dependency to use `StealthVerifier` / `StealthSystem` /
  `AppWindowGuard` from app code.
- **Existing screen reader:** `ScreenReader.swift` (not my file) already builds
  `SCContentFilter(display:excludingWindows:)` excluding all own windows, so OCR
  cannot read the Island. I added `ScreenCaptureExclusion` as the tested,
  explicit rule but could not edit `ScreenReader.swift` to call it.
- **Full Island harness** blocked by other agents' concurrent in-progress
  FeatureIsland edits (item 5 above). Re-run `python3 tools/verify-island` once
  those agents finish.
