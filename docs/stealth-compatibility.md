# Clearly stealth — compatibility matrix (skeleton)

Status: **skeleton**. No real-world share test has been run. Every share mode
below is **UNVERIFIED** because no second device was available. Do not read a
blank or `UNVERIFIED` cell as a pass.

This file is the source of truth for what hiding is *claimed* to work on. UI
copy must never be stronger than the entries here.

## What is actually implemented and verified

| Item | Status | Evidence |
| --- | --- | --- |
| Public mechanism only (`NSWindow.sharingType = .none`) | Applied | `IslandPanelController.swift` sets `.none` before first `orderFront`; `ClearlyStealth/StealthWindowController.swift` mirrors it. |
| Every app-owned window forced to `.none` | Applied | `WindowGuard` re-applies on window update, screen-parameter change, space change, wake and Island show; DEBUG assertion of the invariant. |
| WindowServer reports `.none` window as sharing state 0 on this Mac | Verified (local, WindowServer metadata only) | `tools/stealth-debug/test.sh`: offscreen probe windows reported states `[0, 1]` for `.none` / `.readOnly`. |
| Screen-reader OCR cannot read the Island back | Applied | Existing `ScreenReader` builds `SCContentFilter(display:excludingWindows:)` excluding all own windows; `ClearlyStealth/ScreenCaptureExclusion` encodes the same rule and is unit-tested. |
| Capture framework actually hides the Island pixels (`StealthVerifier`) | Built, runtime UNVERIFIED | Logic + persistence tested headlessly with injected captures. A real run needs Screen Recording permission and briefly shows probe rectangles, so it was not executed in this headless pass. |
| OS / meeting client respects `.none` in a real share | UNVERIFIED | No second device; no real share test. The OS may ignore this legacy flag in ScreenCaptureKit on some builds — this is exactly what the matrix below is meant to settle. |

## Share-mode matrix

Legend: `UNVERIFIED` (not tested) · `PASS` (island absent on receiver, present
on Mac) · `FAIL` (island visible on receiver — a known leak).

macOS build under test: **26B123 (27.2)**. `sysctl kern.osversion`.

| Client | Share mode | macOS build | Result | Notes |
| --- | --- | --- | --- | --- |
| Google Meet (Chrome) | Entire Screen | 26B123 | UNVERIFIED | No second device |
| Google Meet (Chrome) | Window | 26B123 | UNVERIFIED | No second device |
| Google Meet (Chrome) | Chrome Tab | 26B123 | UNVERIFIED | No second device |
| Zoom | Entire Screen | 26B123 | UNVERIFIED | No second device |
| Zoom | Window | 26B123 | UNVERIFIED | No second device |
| Teams | Entire Screen | 26B123 | UNVERIFIED | No second device |
| Teams | Window | 26B123 | UNVERIFIED | No second device |

Add rows for each additional macOS build / client as they are tested. A `FAIL`
must be recorded as a known leak, never deleted.

## Residual surfaces not covered by the flag

From the Clearly design; these remain true regardless of matrix results:

- **Shareable-window picker**: ScreenCaptureKit can still list the window title
  and frame. Mitigated by empty title, `isExcludedFromWindowsMenu = true`,
  accessory activation policy and `LSUIElement` — residual, not eliminated.
- **Other app-owned windows**: enforced to `.none` by `WindowGuard`, but any
  future window created outside `NSApp.windows` before the guard sees it is a
  risk. Native popovers/menus/alerts are banned; build them in-island.
- **Hardware / analog capture**: HDMI capture cards, a phone pointed at the
  screen, display-level remote desktop — not solvable in software.
- **Process/window enumeration** (employer or proctoring software): out of
  scope. Do not attempt to detect or evade it.

## How to fill this in (gate 7)

1. Two devices in the same meeting. Share from the Mac in each mode above.
2. Receiver screenshots what it sees; Mac screenshots its own view.
3. Island visible on the Mac and absent on the receiver in every mode → `PASS`.
   Otherwise record `FAIL` and the exact mode/client/build.
4. Separately run `StealthVerifier` on this Mac (Settings → Privacy → Verify)
   to record the capture-framework result, keyed by macOS build.
5. Re-run on every macOS build change and display-configuration change.

## Copy rules

- Never "undetectable" or "invisible to everything".
- `Verified` copy is bounded: "Hidden from screen capture on this Mac — checked
  on macOS &lt;build&gt;. Other capture apps and share modes were not tested."
- `Failed` copy is loud: "Visible to screen share on this Mac. Do not rely on
  hiding."
- `Unverified` copy: "Hiding not verified. Do not rely on hiding."
