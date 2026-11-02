# Issue

## Meeting intelligence screen OCR stalls

Vision recognition did not return after successful screen capture in native probes on macOS 27.2.

- [x] Unresolved
- [ ] Resolved

Evidence: normal and CPU-only probes reached OCR; both were interrupted. See agents/codex/meeting-intelligence/results/live-validation.md.

## Settings and Meetings navigation lag

Users report severe lag when opening Settings or Meetings and switching pages.

- [x] Unresolved
- [ ] Resolved

## Island floats below the menu bar

The Island is reported to float below the menu bar instead of attaching to the screen edge.

- [x] Unresolved
- [ ] Resolved

<details>
<summary>Original report (historical, unverified)</summary>

# The Island is not a Dynamic Island — it is a floating badge under the menu bar

**Type:** Design / frontend bug
**Severity:** High (the Island is the app's primary surface while dictating)
**Area:** `FeatureIsland` + `IslandPanelController`
**Status:** Open

---

## Summary

The "Island" is not attached to the top edge of the screen or to the camera housing,
and it does not behave like an iOS Dynamic Island. It renders as a rounded glass card
that floats **below** the menu bar with an 8 pt gap, keeps a fixed size, and can be
dragged anywhere on screen.

A Dynamic Island should read as a **continuation of the notch**: its background merges
with the notch / menu bar, it is pinned to the top edge, and it grows **downward** from
that edge as state changes. Today it is a badge that happens to sit near the top.

---

## What it looks like today

- Floating rounded card, **280 × 60** compact / **460 × 160** expanded.
- Vertically positioned at `visibleFrame.maxY - height - 8`, i.e. **below the menu bar
  with an 8 pt gap**, never touching the top edge.
- Background is `GlassSurface` (`.regularMaterial` / macOS 26 `glassEffect`), radius
  **22 / 26** — a card, not a notch-shaped housing.
- Window is `hasShadow = false`, clear, borderless, `.statusBar` level.
- Position is user-draggable and persisted per display (`island.position.<displayUUID>`).
- Hidden by default; only appears while a dictation/meeting session is active
  (`showIdlePill` defaults to `false`).
- Expansion is triggered only by clicking the small title row; the window frame is
  re-set with a hard `setFrame(...)` while only the SwiftUI content animates.

Result: it reads as a floating utility badge, not as part of the notch.

---

## Evidence

| # | File | Line | Observation |
|---|------|------|-------------|
| 1 | `App/SuperflowApp/Sources/SuperflowAppCore/Windowing/IslandPanelController.swift` | 152–166 (`placePanel`) | Position uses `screen.visibleFrame` and `visible.maxY - size.height - 8`. `visibleFrame` excludes the menu bar, so the panel is placed **below** it with an extra 8 pt gap. |
| 2 | same | 106–122 (`refreshPanel`) | Size is hardcoded to `460 × 160` / `280 × 60` and applied with `panel.setFrame(frame, display: true)` — no animated window morph, no content-driven sizing. |
| 3 | same | 100–104 (`movePanel`) | Clamps the panel to anywhere inside `visibleFrame`, so it can be dragged into the middle of the screen. |
| 4 | same | 84–91 (`windowDidMove`) | Saves the dragged origin per display, making "floating anywhere" the permanent state. |
| 5 | same | 42–46 | `hasShadow = false`, clear, opaque off — the glass card edge is the only silhouette. |
| 6 | `Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland/IslandView.swift` | 43–60 | Root is `GlassSurface(radius: 22/26)` + horizontal/vertical padding; no top-edge/flat-top shape, no notch cutout. |
| 7 | `Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland/IslandView.swift` | 47–53 | Idle → pill (optional), otherwise compact/expanded. No "attached" idle state at the notch. |
| 8 | `Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland/IslandMetrics.swift` | 5–20 | Fixed metrics (`280/460`, `60/160`, `topInset = 6`). `topInset` is **never used** by the panel; placement hardcodes `8`. |
| 9 | `Packages/L0-Core/Kernel/Sources/SuperflowKernel/Settings.swift` | 74 | `showIdlePill = false` by default — nothing is attached to the notch when idle. |
| 10 | Repo-wide | — | No use of `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, or any notch/menu-bar geometry anywhere. |

Supporting doc drift: `docs/architecture/design-token-map.md` points at
`FeatureIsland/IslandDragPolicy.swift`, but `IslandDragPolicy` actually lives in
`IslandMetrics.swift`.

---

## Root causes

1. **Wrong coordinate space.** Placement is derived from `visibleFrame` (the area *below*
   the menu bar) instead of `frame` + menu-bar height / notch safe area.
2. **No notch model.** The app never asks the screen whether it has a notch, how tall it
   is, or what the auxiliary areas beside it are.
3. **Card-shaped container.** `GlassSurface` + symmetric padding + large corner radius
   produces a floating card silhouette. A notch extension needs a flat top edge, small
   bottom radius, and an opaque/merged fill.
4. **Decoupled window size and content.** The AppKit window snaps between two fixed
   sizes while SwiftUI animates independently, so the panel can never "grow from" the
   notch.
5. **Free positioning.** Drag-anywhere + persisted origin is fundamentally incompatible
   with an attached surface.

---

## Expected behavior (design spec)

### Attachment
- The Island is **horizontally centered on the active display's notch** when one exists;
  otherwise centered on the display and attached to the **top edge / menu bar**.
- Its **top edge is flush with the top of the screen** (`screen.frame.maxY`), with the
  body hanging downward. No gap between the top of the Island and the top of the display.
- On a notched Mac the Island's top area is **the notch**: same width as the camera
  housing at rest, same black fill, no visible seam. The notch is the Island's idle state.
- On an external/non-notched display it attaches to the menu bar as a black pill that
  visually merges with the bar (same height, same fill) and expands downward.

### Shape
- Flat top, rounded bottom only (bottom radius ≈ notch radius, not a full capsule).
- Opaque black housing (not material/glass) for the attached region so it reads as one
  piece with the notch. Content may use the existing glass treatment **inside** the
  expanded body, but the top band must stay black.
- No shadow above the top edge; shadow (if any) only below the expanded body.

### Motion
- State changes **grow/shrink from the top edge**: width and height animate together with
  the window frame and the SwiftUI content on the same curve/duration (single source of
  truth), never a snap-then-fade.
- Compact → expanded: the Island widens symmetrically around the notch center and the
  body drops down. Expanded → compact: the reverse, ending flush at the notch.
- Reduce Motion: instant size change, no morph, no bounce.

### States
- **Idle (default):** the notch itself, or a minimal black pill. Must exist by default;
  `showIdlePill` should no longer be the only way to see anything.
- **Listening:** compact form shows the live waveform + elapsed time, attached.
- **Processing / complete / degraded / failed:** same attachment, content morphs in place.
- **Expanded:** peek on hover or click, full transcript/controls below the notch.

### Position
- Not freely draggable. At most, allow horizontal offset or per-display opt-out.
- Persisted position must not override attachment; if kept, it may only store the chosen
  display, not an arbitrary origin.
- Must follow the active display: moving to another Space/display re-attaches correctly.

### Edge cases
- Menu bar auto-hide, full-screen apps, Stage Manager, multiple displays with mixed
  notch/non-notch, display hot-plug, resolution change, and clamshell mode must all
  re-attach rather than leave the badge at a stale origin.

---

## Acceptance criteria

- [ ] On a notched Mac, the Island's top edge is flush with the top of the display and
      horizontally centered on the notch, with zero visible gap.
- [ ] The idle state is visible at the notch without starting a session.
- [ ] The top band is opaque black and merges with the notch/menu bar; no glass edge,
      border, or shadow appears above it.
- [ ] Compact ↔ expanded changes animate the **window frame and content together** from
      the top edge; no clipping, no snap, no jump.
- [ ] On a non-notched display the Island attaches to the menu bar and expands downward.
- [ ] The Island cannot be dragged into the middle of the screen by default.
- [ ] Moving between displays / Spaces / full-screen re-attaches on the correct screen.
- [ ] Reduce Motion removes the morph but keeps attachment and final states correct.
- [ ] No regression in the waveform, elapsed timer, partial text, controls, or
      right-click menu.

---

## Technical notes (for the fix)

- Use `NSScreen.frame` (not `visibleFrame`) for the top edge.
- Menu-bar height: `screen.frame.maxY - screen.visibleFrame.maxY`.
- Notch detection / geometry (macOS 12+):
  - `screen.safeAreaInsets.top` (0 on non-notched displays)
  - `screen.auxiliaryTopLeftArea` / `screen.auxiliaryTopRightArea`
  - `screen.localizedName` + display UUID already available in the controller.
- Compute the notch rect as the gap between the two auxiliary areas; fall back to a
  centered pill of fixed width when they are `nil`.
- Drive the panel frame from a single layout model shared with `IslandMetrics`
  (replace the hardcoded `460/160`, `280/60`, and `8`), and animate the frame with
  `NSAnimationContext` using the same duration/curve as `Motion.settle`.
- Replace `GlassSurface` at the island root with an attached housing view
  (flat-top shape + black fill); keep glass for the expanded body only.
- Re-place the panel on `NSApplication.didChangeScreenParametersNotification`,
  `NSWindow.didChangeScreenNotification`, and Space changes.
- Update `docs/architecture/design-token-map.md` (geometry section) and fix the
  `IslandDragPolicy.swift` path.
- Previews: add a notched-display fixture so the shape can be reviewed without hardware.

---

## Out of scope

- iOS-style gesture interactions (swipe-down to expand, long-press).
- Multiple simultaneous live activities.
- Redesigning the expanded content, waveform, or controls beyond what attachment
  requires.

---

## Open questions

1. Should a notched Mac show **only** the notch at idle (zero added pixels), or a
   slightly wider black pill so the waveform is visible without expanding?
2. Is drag-to-reposition a feature we keep (horizontal only, per display) or remove
   entirely in favor of attachment?
3. Should the expanded body use glass over the desktop, or stay opaque black for the
   first ~40 pt and fade to glass below?

</details>

## Swift verification blocked by DeepFilterNet concurrency errors

CI fails compiling DeepFilterNet-mlx MLXArray captures under Swift 6.4.

- [x] Unresolved
- [ ] Resolved

Evidence: Actions run 41356842540 at 4914d8e; compiler and runner setup succeeded, make verify failed.

## Cleanup lacks polarity and quantifier protection

Cleanup can accept meaning-changing negation or quantifier deletion in unprotected text.

- [x] Unresolved
- [ ] Resolved

Evidence: CleanGuard.verify has no hard negation or quantifier comparison; solution v2 requires both.

## Recognition buffering silently drops audio on overflow

A full recognition relay discards oldest audio without warning or entering journal recovery.

- [x] Unresolved
- [ ] Resolved

Evidence: consumeCapture uses bufferingNewest(4096); consumeAudio ignores feed.yield's dropped result.

Hardening progress: polarity/name/quantifier regression coverage added; overflow now surfaces a notice and blocks incomplete insertion while retaining the journal. Physical overflow/recovery and full v2 acceptance remain unverified, so issues stay Unresolved. CI dependency repair remains outstanding.

Overflow regression: a simulated dropped chunk prevents insertion and retains an unfinished session and journal. Physical overflow and recovery remain unverified.

## Dictionary gate bypasses developer context

Textract replacement bypassed Tier B gating; disabled personal entries incorrectly enabled ambiguous replacements.

- [ ] Unresolved
- [x] Resolved

Verification: new regressions failed before the fix; developer-context, disabled-pin and AWS-exclusion tests now pass.

## Dictionary migration depends on optional word list

Without wordfreq, migration silently changes alias tiers and fails to reproduce the bundled catalog.

- [x] Unresolved
- [ ] Resolved

Evidence: two isolated migration runs matched each other, preserved source, but differed from bundled v4.

Mitigation: migration now fails if wordfreq is unavailable. Reproducibility with the original word list remains unverified.

## Developer app gate lacks production context

Production TextContext constructors omit activeAppBundleID, preventing developer-application gating.

- [x] Unresolved
- [ ] Resolved

Evidence: identifier appears in TextContext and gate, but no production caller supplies it. Mixed-language false positives also require policy review.

Latest resolution: Dictionary gate bypasses developer context — failing-before regressions now pass for Textract gating and disabled pins.
