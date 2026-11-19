# Two-pass screenshot review — Dynamic Island rebuild

**Method.** No GUI was opened and no window was raised. All images were produced
by the headless `IslandSnapshotTests` XCTest host (an offscreen `NSHostingView`
inside an `NSWindow` at `(-10000, -10000)`), writing PNGs only when
`ISLAND_SNAPSHOT_DIR` / `IDLE_LAMP_SNAPSHOT_DIR` are set. Pass 1: 86 tests, 0
failures, 156.8 s, 42 PNGs into `screens/pass1/`. Every distinct state below was
opened with `Read` and judged against `DESIGN.md §8.18`, `DESIGN-RULES.MD` and
the matching requirement. Fixes are **requested** here and in `report.md`; the
validation agent does not edit production source.

**Important scope note.** These screenshots are of the Island UI *as it exists
in the working tree at review time*, while four agents are still rebuilding it.
Several judgments therefore describe the pre-rebuild UI; the rebuild must be
re-screened after integration. That limitation is itself graded FAIL/UNVERIFIED
in `review.md`, not treated as a pass.

---

## Pass 1 — first look (screens/pass1/)

| Image | What I judged | Verdict | Fix requested |
|-------|---------------|---------|---------------|
| `notch-idle.png` | Flat top flush with menu-bar edge, concave top fillets, convex bottom, opaque black; 5-cell blue lamp centred under the notch. | PASS | — |
| `notch-hover.png` | Hover shelf/logic present; silhouette still one continuous shape. | PASS | — |
| `notch-live.png` | Mic glyph left, blue silence line right (silence is a visible dotted line, not a dead slab). **Two mic glyphs** (band + no-signal shelf) are redundant. | FAIL (design) | Drop the band mic glyph while the no-signal shelf is visible. |
| `notch-hands-free.png` | Clock `0:00` rolls, meter right, hint shelf is part of the silhouette. Same duplicate-mic issue; "No sound yet." shelf shown in every listening state of the fixture. | FAIL (design) | Same as above; confirm shelf only appears after the 2 s silence threshold. |
| `notch-meeting.png` | Brand pixel disc + `8:27` clock, 24-column barcode (flat dotted line = silence). Redundant no-signal shelf again. | FAIL (design) | Same duplicate-mic fix. |
| `notch-meeting-panel.png` | Expanded card: clock, `1,248 words`, honest `— per minute` fallback, speaker legend, live line with edge fade, Mark / Discard / End meeting. **Legend sums to 101%** (50+38+13). Live line begins mid-word ("side the caret."). | FAIL (honesty) | Largest-remainder rounding so shares total 100%; compute wpm from words/elapsed when the pulse lacks a rate. |
| `notch-history.png` | Recent card, one line per row, selected row shows copy glyph, edge-faded preview, "Click a line to copy it", "Open History". All five fixture rows are identical so truncation variance is untested. Copy glyph reads as "documents", app icon is a dark grid fallback (offscreen host has no app icons). | FAIL (artefact) | Re-screen with distinct row lengths and real app icons before signing off; verify glyph is a copy glyph. |
| `notch-copy-failed.png` | "Not pasted" card, selectable transcript in a `well` tile, TextEdit + 14 words, quiet "Paste again" and one accent "Copy". Only one accent-filled element — correct. | PASS (minor: spec says "Not pasted.") | Add the period, or confirm copy is intentional. |
| `notch-copy-recent.png` | Recent card with transcript tile + Copy. App name truncated to **"Tex..."** despite available width. | FAIL (design) | Widen the app-name column or show the full name with a line limit; "Tex..." is not a name. |
| `notch-notification.png` | Milestone card: pixel spark mark, `1,000 words, dictated by you`, 10-cell drain, dismiss X. Clean, one accent, correct hierarchy. | PASS | — |
| `external-idle.png` | Non-notch display shows an opaque black pill with the five-cell lamp — matches the "pill" requirement. | PASS | — |
| `external-live.png` | **Clipped text**: the no-signal shelf wraps and the second line ends "Check your micr." cut off by the silhouette; shelf mic glyph overlaps the text. | FAIL (clipping) | Widen external listening wings to fit the shelf, or shorten the copy to one line and apply the edge fade. This is the worst visual defect found. |
| `still-0.png` … `still-4.png` | Idle lamp panels, 5 blue cells, stable across frames. | PASS | — |

### Pass-1 fix requests (summary, sent via `report.md`)

1. **F1 (R6/R7):** external-display no-signal shelf clips its text — widen wings or shorten copy.
2. **F2 (R7/R9):** duplicate microphone glyph when the no-signal shelf is shown.
3. **F3 (R9):** meeting talk-share legend must total 100% (largest remainder).
4. **F4 (R9):** derive words-per-minute from words/elapsed instead of `—` when the pulse omits it.
5. **F5 (R15):** re-screen History with varied row content and real app icons; verify copy glyph.
6. **F6 (R10/R16):** "Tex..." app-name truncation is too aggressive.

---

## Pass 2 — second look as a different reviewer

An earlier pass-2 attempt failed to build (`IslandHistory.swift:148` duplicate
`RowReveal`, `PanelViews.swift:80` duplicate `HistoryRow`, `Tokens.swift:51`
member named `Type`) — evidence retained in the first `logs/snapshot-pass2.log`.
After those agents' edits landed, pass 2 was regenerated: 27 PNGs in
`screens/pass2/`. I read the key images again with fresh eyes.

| Image (pass2) | Change vs pass 1 | Fresh judgment |
|---------------|------------------|----------------|
| `external-live.png` | Narrow wing now shows only mic glyph + blue meter; the "No sound yet" shelf is gone. | **F1 FIXED** — no clipped text. The wing is now very small; verify the live-text shelf still fits with real content. |
| `notch-live.png` | Live text line appears: "The newest words stay beside the caret. The new…" with edge fade, single mic glyph, blue meter. | **F2 FIXED**; live text now renders. Good. |
| `notch-meeting-panel.png` | Now shows only the collapsed wing (`0:00`, barcode, X) — the expanded panel with clock / word count / talk-share legend / Mark / Discard / End meeting is **gone**. | **REGRESSION** — requirement 9/15 "meetingEnded(suggestions) → answer" and the expanded meeting panel are no longer visible. F3/F4 moot because the panel vanished. FAIL. |
| `voice-and-submitting.png` | Pixel meter + submitting sweep still draw. | PASS. |

The pass-2 test run itself **failed**: `IslandWaveformWiringTests
testListeningPaintsBlueCellsInTheRightWing` — `XCTAssertGreaterThan failed:
("0") is not greater than ("20") — the meter drew no lit cells in the trailing
wing` (`logs/snapshot-pass2.log`). That is a real regression introduced during
the rebuild, not a fixture artefact. It must be fixed before sign-off.

**Pass-2 verdict:** two image sets now exist, but the suite is red and a key
state regressed, so there are **not two consecutive clean passes** — R19 stays
FAIL. Fix requests from pass 1 that remain open: F3–F6 (F1/F2 are resolved).
New pass-2 request:
- **F7 (R9, R7):** restore the expanded meeting panel (stats, suggestions, End
  meeting) and make the listening waveform paint lit cells in the trailing wing.
