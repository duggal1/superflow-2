# DESIGN.md — Superflow

**Audience:** coding agents building the app.
**Status:** the spec. If code and this document disagree, the code wins — then fix this document in the same change.

**Precedence:** `DESIGN.md` (this file) → `DESIGN-RULES.MD` (superseded where it conflicts) → `DESIGN-REBUILD-GUIDE.MD` (Pass 1) → Pass 2 (structure) → Pass 3 (dashboard, controls, Models, first-run). This file records the result of all five, not the proposals they started from.

Numbers are the spec. When a task says "more X", "sharper" or "smoother", tune the numbers. Do not replace the system and do not add effects.

---

## 0. Pass 3 (clarity, audio, structure) — authoritative overrides

Pass 3 is the newest layer and wins over everything below where they disagree. This section records what the code now does.

### 0.1 Pixel law

1. Pixel clarity is the product: a half-pixel edge is a bug.
2. Every frame origin, size, offset, padding and radius lands on the 1/scale grid. Derived lengths go through `Pixel.snap`; symmetric shapes use `Pixel.snapEven`. No `.offset(x: 0.5)`.
3. The 4 pt grid: 4, 8, 12, 16, 20, 24, 32, 48, 64. A value off the list needs a written reason.
4. One left edge: detail content starts 32 from the sidebar. Labels share a column; trailing controls share a right edge; the **glyph**, not its 32 pt hit target, sits on the content edge.
5. Text comes from `AppType`. No raw `.font(.system(size:` outside `AppType`, `UIComponents`, `Icons` and SF Mono (`design: .monospaced`). Numbers are tabular and their width is reserved.
6. Icons are bare SF Symbols at 14, 16, 12 or 9, centred by frame, never by padding.
7. No strokes, shadows or gradients. The only ring is ours, drawn for keyboard navigation only.
8. Motion is state-driven: `.snappy` for small, `.smooth` for large. Nothing bounces or loops. Reduce Motion renders the end state.
9. Verify by measuring: 2x crops, dark and light, 400% zoom, `pixelAudit` silent.
10. Report what could not be verified.

### 0.2 Ring and focus

The system ring is off at four levels: `window.contentView?.focusRingType = .none` plus `makeFirstResponder(nil)` in `WindowChrome`; `.focusEffectDisabled()` at the main-window and onboarding roots; `.focusEffectDisabled()` on every `.focusable()`; `InputModality.shared.start()` at launch. Our ring is `keyboardFocusRing(radius:)`: 2 pt accent, offset 2, keyboard navigation only, never after a click or on open. `FocusStep` remains for Increase Contrast only.

### 0.3 Type

Use Albert Sans for sans-serif text. Normal text, descriptions, and reading roles use weight 325. Labels, medium text, metrics, and sans-serif titles use weight 350. Keep the existing serif display face. `AppType` retains its existing sizes and tracking; The bundled Albert Sans has proportional digits, so numeric widths can change as values update.

### 0.4 History

- Bar: search only. Copy and Delete live in the detail header, right-aligned, 32 pt targets 4 apart, group pulled out 8 so the glyph edge equals pane right − 32.
- Rows: 56 tall, icon 20, gap 12, transcript as the title (13/500), meta 12/350 with relative time that re-renders every minute and a tabular word count. No speech rows are dimmed and carry no count. No date titles, no `DateFormatter`: all dates go through `Humanize`.
- Detail order: header, audio preview when a clip exists, Cleaned/Raw, transcript. Meta row indented 32, three elements 12 apart. Copy morphs to a checkmark for 1.2 s.
- List pane leading inset 20; detail horizontal padding 32 and bottom 48.

### 0.5 Audio archive

- Dictation only. AAC `.m4a`, 16 kHz mono, 32 kbps, in `Application Support/Superflow/Audio`, excluded from backup.
- The audio consumer tees the same buffers to the archive. Peaks are computed while writing, 20 per second, one byte each, and stored on the session row. `audio_duration REAL` and `audio_peaks BLOB` are the only schema additions (v3). The pass 4 card ignores both: the file is the source of truth, and the spectrogram is computed from the audio itself.
- On, 7-day retention by default. "Don't store transcripts" means no file is ever opened. Zero-word sessions discard their clip.
- Deleting a session defers file removal six seconds; Undo cancels it. A sweep runs at launch and daily, removing expired files and nulling both columns for missing clips.
- Preview is a **pixel spectrogram**, not a waveform bar. The clip is decoded once (cached, 96 MB) and analysed into 8 log bands × one column per 25 ms (Hann 512, hop 400). Cells are ≈4 pt squares with a 2 pt gap, solved so the last column ends exactly on the card's content edge. Low bands sit at the bottom: hum on the bottom row, "s/sh" on the top. Unplayed cells are the neutral control steps; the scan column is `Tok.text`, the two cells behind it are a dithered `Ramp.blue[4]` cooling trail, everything older is the brand ramp. The picture develops in 14 whole steps on load (Reduce Motion starts finished). Dragging plays a 90 ms Hann grain at the pointer (tape-head scrub) and pauses/resumes playback; a click seeks. The readout is the tooltip, in tenths, floored so 59.96 s never prints 0:60.0. Transport row 32: play/pause glyph, readout, and a hover-only "Drag to hear" hint that is always laid out. No rate button: a pitch-shifting node would break the sample clock. Space toggles, arrows step 1 s.

### 0.6 Shortcuts and Dictionary

Composer cards are deleted. Page body: scope `Personal | Shared`, 16 below it a search row with the Import/Export menu and an accent Add (32 tall, the only accent-filled control). Title to scope and search row to list are 32. Adding and editing happen in `DialogHost`. Rows are 36, two flexible columns, no pills or per-row cards; Delete is the context menu. Shared is an honest empty state.

### 0.7 Dialogs

`DialogLayer` sits at the window root above `MenuLayer`: flat scrim (`Tok.modalScrim`, 0.28 light / 0.55 dark), solid `Tok.surface` panel 480 wide, padding 24, radius 16, fields 32 tall radius 8, field gap 16, footer buttons 32. Opens at 0.97 scale with a 6 pt rise and fade; closes in 120 ms. Esc cancels, ⌘Return confirms, first field focused, Add disabled until valid. `.sheet`, `.alert`, `.confirmationDialog` and `.popover` are banned.

### 0.8 Settings

- Rows 48 tall, bare 14 pt glyph in a fixed 20 pt column, gap 12, label `AppType.label`; cards 24 apart, at most three cards per tab and five rows per card.
- Tabs: General (Name, Appearance, Launch at login), Dictation (Speech model, Clean up; Hold to talk, Double-tap window, Meeting hold), Text (four toggles; Paragraph break + Block length; Code Speak), Meetings (Meetings in stats, Speaker separation), Privacy (Don't store transcripts, Keep audio, Delete audio after; Delete transcripts, Diagnostics, Licenses), Advanced (Typing speed, Interactive deadline, Background deadline, Cleanup workers, Cleanup compute).
- Context profile, the cleanup-context dropdown, help text, the three block steppers and the Commands expander are cut. Block length maps Short 15/25/35, Standard 25/35/45, Long 40/60/80 onto the existing line-format properties.
- Toggle: track 40 × 24, knob 20 (26 pressed), inset 2, Blue 600, white knob, haptic on flip; hit area 32.
- Slider: custom `AppSlider`. Track 4, thumb 16 (18 dragging), 280 wide, 64 readout, `Tok.text` thumb. `TimingSlider` is gone.
- Code Speak shows a live result when on and opens Commands in a dialog.

### 0.9 Lint

`tools/lint-forbidden` fails on: `.focusable(` without `.focusEffectDisabled(`; `focusRing(`; event monitors outside `InputModality`; raw font sizes outside `AppType`/`UIComponents`/`Icons`/SF Mono; `DateFormatter` or `.formatted(date:` in `FeatureHistory`; `AVAudioPlayer` outside `UIComponents/AudioPreview.swift` (one player, in the shared component); `AVAudioFile(forWriting` outside `AudioArchive`; `.sheet`, `.alert`, `.confirmationDialog`, `.popover`; native `Slider(` outside `AppSlider`; `TimingSlider`; `SettingRow("` (no glyph); `help:` in Settings; raw `.white` outside the toggle/primary-button files.

### 0.10 Measured constants (source of truth)

| Item | Value |
|---|---|
| Page left edge | 220 + 32 = 252 |
| History row | 56 tall, icon 20, gap 12, title 13/500, meta 12/350 |
| History detail header | 32 row, icon 20, gap 12, actions 4 apart, glyph edge = pane right − 32 |
| Meta row | indent 32, elements 12 apart |
| Audio card | padding 20, 8-band spectrogram, cells ≈4, gap 2, transport 32 |
| List controls | scope→search 16, title→scope 32, search→list 32, Add 32 |
| Dialog | 480 wide, padding 24, radius 16, field 32/8, field gap 16, footer 32 |
| Toggle | 40 × 24, knob 20/26, inset 2 |
| Slider | track 4, thumb 16/18, 280 + 64 readout |
| Settings row | 48 tall, icon column 20, gap 12, cards 24 apart |

These numbers are asserted by construction (tokens and frames), not by a screenshot pass.

### 0.11 Open verification (honest list)

The owner asked for no builds or runs during this pass because SwiftPM was freezing the machine, so nothing below is measured at runtime:

- The blue ring: the four-level fix is in place, but which level removed it, and the ring's cause, are unconfirmed. Needs Keyboard navigation on and off, every route and every dialog.
- 2x screenshots, 400% edge crops, and `pixelAudit` output: open. No measured screenshot table is attached.
- `Font(NSFont)` at weight 350 and whether `.monospacedDigit()` tabularises on it: unverified.
- AAC 16 kHz mono at 32 kbps plays acceptably; `AsyncStream.makeStream`; `onContinuousHover`; `contentTransition(.symbolEffect(.replace))`; every new SF Symbol in the Settings table: unverified at runtime.
- `TextEditor` placeholder padding in `AppEditor`: unverified.
- "Always show Island" reinstates the General switch under `island.alwaysOn`. It draws a five-cell lamp below the notch, or a small black pill on an external display, and opens the five-item history preview. `island.liveText` controls the visible live shelf; streaming stays on.
- The Settings sliders and toggles, the Code Speak expansion and the dialog focus order were checked by construction only.
- The spectrogram's FFT tuning (`tilt`, `range`, the 40/110/180 level thresholds) is unmeasured on real speech. Say "sign off" and check that the "s" is in the top rows; if the picture is mush, tune those three constants, not the grid.
- Tape-head grain clicks, the sample-clock playhead (`startSample + playerTime.sampleTime`), and output-device route changes are unverified. The engine does not react to route changes yet.
- The spectrogram caches decoded samples (96 MB cap) and guards against files over 15 minutes at 16 kHz; no real archive has been measured against those limits.
- The Island's new marks (hover pixel, three-cell wait, lock, check, notice spark/flame/burst, blue silence meter, barcode) are drawn by construction only. They have not been seen on a real notch at 2×.
- The Island meter now draws its whole trail (24 entries, 11 or 24 columns) at 30 Hz and resets at the start of every session; the tick count and CPU cost are unmeasured. The warming status mark adds a second 0.14 s loop to the sidebar footer while a model loads or the microphone is live; its cost next to the scan rail is unmeasured.

---

## 1. Protocol

1. **Declare tokens first.** Before writing a view, list the surface steps, spacing, radii, type roles, control heights and SF Symbols it uses. Use only those.
2. **Native before custom.** Native controls, native glass, native menus, native shortcuts. Custom only where this document names the component.
3. **Build with token names.** No literals for colour, spacing, radius or control height outside `DesignSystem`.
4. **Run the checks** in §16. Every command returns zero hits except the named exceptions.
5. **Verify** in light and dark, Increase Contrast, Reduce Transparency, Reduce Motion, minimum window size and collapsed sidebar.
6. **Delete** anything that carries no information and no affordance.

If an API in this document does not compile against the installed SDK, check the current name in Xcode. Do not fake it.

---

## 2. What the app is

- **Target:** macOS 15.0. Features that exist only on macOS 26 are behind `#available(macOS 26.0, *)` (`glassEffect`, `scrollEdgeEffectStyle`). Everything else must work on 15.
- **Window:** default 960 × 620, minimum 880 × 560. Main window is non-opaque so the sidebar blur can see the desktop; the detail pane paints `Tok.bg` edge to edge. Onboarding is a fixed 640 × 520.
- **Shell:** a custom `HStack` (`MainWindowRootView`) with `Sidebar` + detail. There is **no** `NavigationSplitView`, no system `.toolbar`, no `.searchable`, no `Table`, no `ToolbarItem`, no `.popover` anywhere in the app.
- **Sidebar:** 220 pt, full height, `NSVisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)`, first row at y = 52, 32 pt rows 2 pt apart, fixed 20 pt icon column, one `washStrong` capsule that slides with `matchedGeometryEffect`. Icon and label are both `Tok.text`.
- **Page chrome:** `PageBar` 52 pt; title starts at y = 60; one left edge at `Layout.pad = 32`. Wide pages are 880 pt; Settings is 640 pt; History and Meetings list panes are 320 pt.
- **Route change:** opacity cross-fade only. View models live above `RouteView`, so `.id(route)` never resets them.

---

## 3. Rules

1. **Paper, ink, one accent.** Blue 600 `#2563EB` is the only brand colour. Status hues exist only inside badges and dots.
2. **No borders. One ring, ours.** Surfaces separate by luminance step, never by stroke. The only strokes are `ContrastStroke` (Increase Contrast edges) and the 2 pt accent `keyboardFocusRing`, which appears for keyboard navigation only, never after a click or on open (pass 3 §0.2). `FocusStep` remains for Increase Contrast. No `Divider()`, no hairlines, no outlined cards.
3. **Two layers.** Navigation floats on system glass or native blur. Content is solid. Never swap them.
4. **Glass and blur are system-made, and only for floating chrome.** `glassEffect`, `GlassEffectContainer`, `NSVisualEffectView`, system materials. Never fake them with gradients, strokes, opacity stacks or hand-rolled blur. Glass appears on the sidebar menu panels, toasts and the command palette, and nowhere else. The Island is the opposite: opaque black, no material, no shadow (§8.18).
5. **Icons are SF Symbols.** Only. No Lucide, Heroicons, Hugeicons, Phosphor, Font Awesome, emoji, PNG or custom SVG. **Vendor marks are the only exception, and they are the vendors' real artwork**: the NVIDIA eye renders in the vendor's own green (`Tok.brandNvidia`) from the bundled logo asset, and the S1-mini plate is the vendor's own raster, clipped to a rounded tile. A vendor mark is never recoloured to `Tok.text`.
6. **Dark mode is first-class.** Check every view in both modes.
7. **No glow, no gradients, no shadows on content.** Depth comes from the surface ladder. The only shadow in the app is the button's inner highlight/blur (§8.1).
8. **Every pixel is justified.** Tokens only. Whole points. A 1 pt misalignment is a bug.
9. **Motion explains, never decorates.** Reduce Motion renders the final state.
10. **Text is real text.** Selectable where it is the user's words, VoiceOver-readable, never behind pixel art.
11. **The slop test.** Swap the logo. If the screen could belong to any other dictation app, redo it.

---

## 4. Tokens

Source: `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Colors.swift`.

### 4.1 Surface ladder

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#F4F4F4` | `#0A0A0A` | canvas, titlebar, page bar, list panes |
| `surface` | `#FFFFFF` | `#171717` | cards, hovered list rows |
| `well` | `#EDEDED` | `#0F0F0F` | inset fields and tracks inside a card |
| `control` | `#EBEBEB` | `#1F1F1F` | buttons, selected rows, menu rows |
| `controlHover` | `#E3E3E3` | `#262626` | hover |
| `controlPressed` | `#DADADA` | `#2E2E2E` | pressed |
| `field` | `#EAEAEA` | `#101010` | search and fields sitting on the canvas |
| `fieldHover` | `#E3E3E3` | `#151515` | field hover / focus |
| `island` | `#000000` | `#000000` | the Island body only — opaque black so it merges with the hardware notch |
| `statusOK` | `#16A34A` | `#4ADE80` | engine ready disc (sidebar footer only) |
| `statusBad` | `#DC2626` | `#F87171` | engine permission-failure ring (sidebar footer only) |

Alpha washes, for translucent backdrops only:
`wash` = black 5% / white 7% (sidebar hover); `washStrong` = black 9% / white 12% (sidebar selection).

### 4.2 Text

| Token | Light | Dark | Use |
|---|---|---|---|
| `text` | `#0A0A0A` | `#FAFAFA` | primary |
| `text2` | `#666666` | `#A3A3A3` | secondary, labels, notes |

There is no `text.3`. Two levels only.

### 4.3 Accent

Blue 600 base, blue 500 hover, blue 700 pressed. Nothing darker, ever.

`accent #2563EB`; `accentHover #1D4ED8 / #3B82F6`; `accentPressed #1D4ED8`; `accentText #2563EB / #60A5FA`; `accentSoft #DBEAFE / #2563EB at 17%`; `accentFill #DBEAFE / #2563EB at 50%`; `onAccent #FFFFFF`.

`accentFill` is the download row's progress fill, the one place the accent is a
large area: at `accentSoft`'s 17% a dark card turned the fill navy instead of blue.
It is not a second accent — same blue 600, one stronger alpha.

One accent-filled element per view. The bar's primary action is it.

### 4.4 Action text and the scrim

- `textAction` — light `#2E2E2E`, dark `#E5E5E5`. One tiny step below `text`. Text links only: "Open Settings", "Get model". Hover promotes to `text`, never to the accent.
- `scrim` — black at 18% (command palette only).
- `brandNvidia` — `#87D501`, the vendor's own green. The only non-blue hue in the app, and it appears only inside a vendor mark.

The Sapphire button tokens (`buttonBorder`, `buttonHighlight`, `buttonInnerRest`, `buttonInnerHover`) and the button edge they drew are deleted; §8.1 describes the flat button.

### 4.5 Space, radii, control heights

4 pt grid: 4, 8, 12, 16, 24, 32, 48, 64. Page padding 32. Section gap 32. Card padding 20 (dense cards 8 + 12 inner). Prose measure 720.

Radii: `card 16`, `nested 12`, `field 8`, `badge 8`, `chip 6`. Buttons are capsules.

Control heights: text buttons are **24** (inline in a row, Replay) or **28** (bars, cards, onboarding) and nothing else — 32 does not exist for a text button. 32 is the search field and `BarIconButton`. The bar is one vertical rhythm: search 32, text buttons 28, icon buttons 32, all centred on y = 26.

---

## 5. Type

Source: `AppType.swift`; `Typography.swift` is display-only.

**One UI face: SF Pro**, through `AppType`. Every label, row, control, menu, note and line of body text resolves through `AppType`; there is no second UI face. Reading roles sit at weight **350** (between Light and Regular) so light text on dark does not read heavier than it measures, and **500** is reserved for labels you scan. The one exception is `metric`: **400**, because a number is read, not scanned. Numbers use `.monospacedDigit()`.

| Role | Face | Size | Weight | Tracking |
|---|---|---|---|---|
| `caption` | SF Pro | 12 | 350 | 0 |
| `body` | SF Pro | 13 | 350 | −0.1 |
| `label` | SF Pro | 13 | 500 | −0.1 |
| `reading` | SF Pro | 15 | 350 | −0.2 |
| `title` | SF Pro | 15 | 500 | −0.2 |
| `metric` | SF Pro | 28 | 400, tabular | −0.6 |
| display `displayS` | Serif Vinci Italic | 28 | — | −1.4 |
| display | Serif Vinci Italic | 40 | — | −2 |

The display face is the brand face, not a second UI face: it appears only in page titles (28) and onboarding titles (40), never upright and never below 28. Line height 0.98 / 0.96. UI tracking comes from the role table above, never from a view.

Sentence case. Numbers use `.monospacedDigit()` where they change in place and their width is reserved. Font smoothing is the system default (anti-aliased) on every `Text`; no view disables it.

SF Mono 12 and 13 (`design: .monospaced`) are the only fixed faces outside `AppType`: code, identifiers and flags. `Typography.displayFont(size:)` and `displayTracking(size:)` are the only remaining `Typography` entry points.

Both bundled faces are registered by `AppFont.registerBundledFonts()`; `validateDisplayFont()` reports a miss without trapping. `Typography` falls back to the system serif for titles if the bundled display face is unavailable. The bundled Albert Sans asset is retained for older builds but is no longer used by any view.

---

## 6. Icons

Source: `Glyph.swift`, `Icon`.

One enum, bare symbols, `.symbolRenderingMode(.monochrome)`, sizes exactly 14 (rows), 16 (bar), 12 (buttons), 9 (dropdown chevron). No enclosures (`*.circle`, `*.square`, `*.rectangle`), no badges, no third-party family. `validateGlyphs()` runs at launch in DEBUG.

The dashboard metric glyphs are open shapes: `words = text.cursor`, `timeSaved = hourglass`, `speed = gauge.with.dots.needle.33percent`, `streak = flame` (fallbacks `character.cursor.ibeam`, `timer`, `bolt`, `calendar.badge.checkmark`). Each draws at 14 pt Regular in a fixed 16 × 16 box in `text2`, so no glyph can push its label. `models = cpu` (fallback `shippingbox`), `minus = minus`; `plus` is `add`. Every icon-only control has an accessibility label. An icon that carries no meaning is deleted.

Vendor marks are the only non-SF-Symbol images: `NVIDIAIcon` (the real eye, `Tok.brandNvidia`, width-given because the mark is wider than it is tall — `aspect = 248.899 / 164.698`) and `S1MiniMark` (the vendor's raster, clipped to a rounded tile). Both live in `SuperflowIcons`; `ModelMark` gives each Models row its own real mark (speech = the eye, cleanup = the plate, meetings = a glyph, because it is a FluidAudio diarizer rather than a vendor model), and onboarding step 3 uses both vendor marks. There is no second copy of either mark.

---

## 7. Shell and page chrome

Source: `MainWindowRootView.swift`, `Surfaces.swift` (`Page`, `SplitPage`, `PageBar`, `PageTitle`).

```
y 0   ─────────────────────────────  traffic lights over the sidebar; bar on the canvas
      PageBar 52: search 32, text buttons 28, icon buttons 32, all centred on y = 26
y 52  ─────────────────────────────
      8 gap
y 60  Title in display 28, ending in the pixel stop
      subtitle only where it carries live information
      content
x = sidebar edge + 32 for search, title, subtitle, cards, graph, list-row icons
```

- `Page` owns the bar, title and top inset. `SplitPage` owns the bar and title; panes scroll themselves.
- Search lives in the bar (`SearchField`), never in the page body. One primary action per page, in the bar.
- Bar controls: `BarIconButton` (bare at rest, hover fill, 32 × 32), `AppButton` (text), `ActionMenu` (ellipsis → `MenuLayer`).
- `⌘1`–`⌘7` switch routes; `⌘F` focuses search; `⌘K` opens the palette; `⌘⌥S` toggles the sidebar. All are menu commands too.
- `WindowDragArea` on the sidebar top and the bar performs window dragging. `isMovableByWindowBackground` is false for the main window.

The sidebar has **seven** rows — Dashboard, History, Dictionary, Shortcuts, Meetings, Models, Settings — no section headers, no wordmark, no divider, no collapse control. Seven 32 pt rows 2 pt apart is 236 pt, which fits. `SidebarStatus` is a 6 pt dot plus one word at the bottom.

Sidebar glyphs are the specific, open Apple symbol for the page, not the stock pick: `chart.xyaxis.line` (Dashboard), `text.line.first.and.arrowtriangle.forward` (History — a transcript with a play head, because every row can be replayed), `character.book.closed` (Dictionary), `command` (Shortcuts), `person.2.wave.2` (Meetings), `memorychip` (Models), `slider.horizontal.3` (Settings). The gear is the most drawn glyph in software, so Settings uses three tuning sliders instead. All bare, unenclosed, 14 pt Medium in the fixed 20 pt column, tinted `Tok.text`.

---

## 8. Components

All shared components live in `Packages/L4-UI/UIComponents`. Features compose them and never build raw controls. Every component below is the written spec rung 4 requires.

### 8.1 Button

Source: `Buttons.swift` (`ButtonKind`, `AppButtonStyle`, `AppButton`, `IconButton`).

Every text button in the app is a flat capsule:

- **Height:** 24 or 28. Nothing else; `AppButton` asserts it in DEBUG. Padding 10 at 24, 12 at 28. Label 12 Medium at 24, 13 Medium at 28.
- **Primary:** `accent`; hover `accentHover`; pressed `accentPressed`. Label white (`onAccent`).
- **Secondary:** `control`; hover `controlHover`; pressed `controlPressed`. Label `text`.
- **Quiet:** no fill at rest, label `text2`; hover and press add a `wash` capsule and promote the label to `text`.
- **Link:** no fill at rest, label `textAction`; hover and press add a `wash` capsule and promote the label to `text`. Used for text links only ("Open Settings", "Get model").
- **No edge, no inner shadow, no gradient.** The Sapphire edge and its two inner-shadow tones are deleted.
- **Hover animation:** `easeOut 0.10` in, `0.22` out. Press scale 0.98 — 0.92 for controls 28 pt or smaller (`StepChip`).
- **Pointer:** `clickable(enabled)` on every button. Disabled keeps the arrow and 0.4 opacity.
- **Focus:** `focusStep` — one `wash` fill step, no outline (§13).
- **Increase Contrast:** the shared `contrastStroke` and the `FocusStep` ring are the only edges.

`IconButton` is a bare symbol in a 24 × 24 hit area with a hover fill. `BarIconButton` is 32 × 32 in the page bar.

At most one accent-filled element per view.

### 8.2 Card

Fill `surface`, radius 16, padding 20, `contrastStroke`. No border, no shadow, no nested card.

### 8.3 Search and fields

`SearchField`: capsule, 32 tall, `field` fill, one fill step on hover/focus, caret `accent`, I-beam preserved, no ring, clear button appears only with text. `AppField` / `AppTextField`: plain `TextField`, 8 pt radius, `well` inside a card and `field` on the canvas, one fill step, caret `accent`, `contrastStroke`. `AppTextEditor` is the same recipe, multiline. `PracticeField` is the onboarding sandbox field: `surface`, 8 pt radius, selectable prose.

### 8.4 Segmented

Capsule track (`surface` on canvas, `well` on card), no outline, 2 pt inner padding, 24 pt items, 12 Medium, one `matchedGeometryEffect` thumb that slides, `Motion.slide`, arrow keys, `focusStep(Capsule())`.

### 8.5 Toggle

38 × 22 track, 18 pt knob stretching to 22 while pressed, `accent` when on (`accentHover` hover, `accentPressed` pressed), `controlPressed` when off, 32 pt hit height, `focusStep(Capsule())`, `snappy` travel, `clickable`. No ring.

### 8.6 Toggle row and setting row

`SettingRow`: label 13 Medium on the left, one 280 pt control column on the right, 44 pt minimum height, no `help` parameter (so help text cannot come back), no hover fill, no divider. `SettingsCard`: `Card(padding: 8)` with 12 pt inner inset, so text lands on 20.

### 8.7 Dropdown and ActionMenu

Every `Picker`, `Menu` and `.popover` in the app is one of these. Triggers use the button geometry plus `focusStep()`. Panels render in the root `MenuLayer`, system glass (or `surface` under Reduce Transparency), radius 16, 6 pt inset, 32 pt rows, 2 pt gaps, row radius 10. **One highlight shape slides between rows** (`smooth 0.18`) instead of each row flashing its own fill. No `.popover`, no arrow chrome, no `.focusable()` without `.focusEffectDisabled()`. Keyboard: up, down, return, escape. Outside click closes. The panel flips up near the bottom edge.

### 8.8 Slider and stepper

`AppSlider` is custom (pass 3 §0.8): 4 pt `controlPressed` track, `accent` fill, `Tok.text` thumb 16 (18 while dragging), 280 wide with a 64 pt right-aligned tabular readout and a 16 pt gap. The thumb follows the pointer continuously while the value snaps underneath, then settles on release. Every track shares one left edge. `TimingSlider` and the native `Slider` are gone; the native control survives only as `AppSlider`'s VoiceOver representation.

`AppStepper` is a trough, not chevrons: `Tok.well` capsule, 28 tall, 2 pt padding, two 24 pt round chips (`minus`, `add`) with a tabular value between them. Hover and press fill the chip (0.92 press scale). Hold a chip to repeat — 380 ms, then 90 ms, then 45 ms after eight ticks. Drag the value sideways to scrub, 8 pt per step, with grab cursors. The value rolls with `.numericText`; a nudge against a bound ticks the trackpad. VoiceOver adjustable.

### 8.9 KeyRecorder, KeyCap, Badge, Dot

`KeyRecorder` is a keycap that records the next chord; Escape cancels. `KeyCap` is a fill step, not a shadow: the lip is a second surface 2 pt behind the face. `Badge` is a tinted fill plus coloured text, no edge. `DotView` is a 6 pt status dot.

### 8.10 Empty state

`PixelStop(cells: 11, cell: 4 / 3)` + title (display 28 for pages, 15 Medium for panes) + one sentence naming the next action. No icon stack, no repeated toolbar button.

### 8.11 Toast

System glass capsule, 40 pt tall, 13 pt text, one quiet action; rises 8 pt and fades over `settle`. `ToastHost` owns placement.

### 8.12 Command palette

`⌘K`. Scrim `Tok.scrim`, `FloatingPanel` 560 wide, 40 pt search row, arrow/return/escape, wrap-around selection, query reset on close of the palette. Reduce Motion removes the scale.

### 8.13 DownloadCard

Source: `DownloadCard.swift`. One card for every model download, in Settings, onboarding and the Models page. Five states, never a boolean:

- **idle** — quiet surface, detail line, trailing control.
- **downloading** — the row fill is `accentSoft` with a **pixel front**: the solid fill ends in a 16 pt band of 4 pt cells that dissolve (density 0.8, 0.55, 0.32, 0.14), snapped to the grid and animatable so it glides. With a known size the card grows 72 pt and shows the rate, the bytes and the time left over a `ThroughputStrip`.
- **verifying** — full fill, "Verifying".
- **installed** — the fill stays full and fades out over 450 ms; the card returns to a quiet surface and carries no colour.
- **failed** — no red fill. The detail line carries the message, the trailing slot carries `Badge("Failed")` and Retry.

One density: leading 24, height 64, title 13, gap 12. Padding 16; +72 while the readout shows (8 top, 48 strip, 16 bottom). `ProgressRow` is deleted.

### 8.14 Waveform

Source: `new-waveform.swift`.

- `WaveformView(engine:phase:)` is the only waveform drawing path. It is a `Canvas` on a 30 fps `TimelineView`, 3 pt bars with 2 pt gaps, round caps, whole device pixels, edge fade by per-bar opacity (never a gradient), newest bars `Tok.accent`, oldest `Tok.accentPressed`.
- `WaveformEngine` owns smoothing, peak-per-slot history and the idle/listening/processing states. It does not own the microphone.
- `LevelsWaveform(levels:)` feeds the same engine from a snapshot (Island, Meetings).
- Reduce Motion uses the calm (no-wave) processing target. The loop stops 700 ms after idle.
- There is no second waveform implementation.

### 8.15 Mic test

Source: `waveform-mic-test.swift`, `MicLevelSource.swift`.

`MicTestView` is the only mic test: 14 dots on a baseline, dots grow into pills as level rises, peak-hold, `Tok.accent` / `Tok.accentPressed`, 30 fps canvas, `AppButton` for Test/Stop/Open Settings, sentence-case status copy. It uses `AVMicLevelSource` by default and `FakeMicLevelSource` in previews. It never runs during a dictation session. Onboarding embeds the same component; there is no duplicate mic meter.

### 8.16 Pixel identity

Source: `PixelStop.swift`, `PixelField.swift`, `PixelDiscFlight.swift`.

- **Pixel full stop:** 5 × 5 cells at 1.5 pt (7.5 pt). Every page title ends in it. Onboarding lands the same 5 × 1.5 stop, so the brand mark is one size everywhere.
- **Pixel field:** deterministic noise, three tones (deep = draw nothing), 16 pt cells, 14-step radial reveal, optional drift. Never behind text; text frames are cleared through preference keys.
- **Pixel disc flight:** 5 cells, 16 pt home cell, sine arc, lands on a live-measured slot; Reduce Motion renders the landed state.

### 8.17 Models page

Source: `FeatureSettings/ModelsView.swift`. Models have their own sidebar route (`⌘6`); Settings contains no model controls. One page, grouped by what the model does — Speech, Cleanup, Meetings.

- **No hero.** The page is the three groups. The only subtitle is `"\(installed) of \(total) installed."`.
- **Rows.** One `DownloadCard` per model: 64 tall, a 24 pt `ModelMark`, name 13 Medium, one sentence, then all five download states. Rows are fed by the same `ModelProvider` / `SpeakerDiarizer` ports onboarding and Settings use; there is no second download path. Cancel invalidates the row's token, so a late progress callback cannot repaint it.
- **Marks.** Speech carries the NVIDIA eye, cleanup carries the S1-mini plate, and meetings carries a glyph — the diarizer is FluidAudio, so there is no vendor artwork to show. The plate is the vendor's real mark, never the NVIDIA eye; `S1MiniMark` is that one asset, shared with onboarding.
- **Cleanup is on for every transcript by default.** `AppSettings.cleanupEnabled` ships `true`, the pipeline adds the cleanup stage for dictation and meetings whenever the model is on disk, and onboarding downloads S1-mini with the speech model. The S1-mini row therefore reads **Active** once installed; turning the setting off leaves the model installed and drops the badge to **Installed**.
- **Names come from the registry.** `ModelProfile` is the single source: the speech row takes `displayName` and the app's default profile (`AppSettings.asrProfile`, currently `nemotron-3.5-asr-streaming-0.6b`), so a rename lands on the Models page and in onboarding at the same time.
- **Groups.** `SectionHeader` per kind (Speech / Cleanup / Meetings), no note; 8 between rows, 12 from the header to the first row, 32 between groups, page padding 32, one left edge. Rows are **not** clickable as a whole; only their buttons are.
- No footnotes, no info icons, no spec chains.

### 8.18 The Island

Source: `FeatureIsland` (all views and geometry) plus `IslandPanelController.swift` and `IslandBridge.swift` in AppCore. Three words: **attached, alive, smooth**. It is not a floating badge and it is not glass; it is the hardware notch, extended.

**Silhouette.** Flat top flush at `screen.frame.maxY`, concave top fillets that flare into the menu bar, convex rounded bottom. `NotchShape` draws it with true quarter-circle Béziers (kappa `0.5522847498`), never quadratics, so the radii read as circles at 8× zoom. The shape is `body.width + 2 × top` wide; the flares live outside the body.

**One window, one shape.** The panel is created once at `IslandLayout.canvas` (520 × 360), pinned flush to the top edge, centred on the notch, and ordered front at launch. Its frame never animates and never changes size; the window moves only while the Island is idle (invisible) and only with `setFrame(display: false)`. All motion is one SwiftUI animation on the shape and its radii, so shape and content share one `Transaction` and retarget mid-flight without restarting. `IslandPanel.constrainFrameRect` returns its argument, or AppKit would push the panel below the menu bar.

**Notch geometry.** `NotchGeometry` is the only thing that reads a screen. It uses `frame`, `safeAreaInsets.top`, `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, and snaps the centre to a device pixel. It never reads the menu-bar-excluding rectangle. Notch width and height are never hardcoded.

**States.** One reducer, one phase:

| Phase | Shape | Content |
|---|---|---|
| `idle` (notch) | the notch rect, drawn `Tok.island`, invisible on hardware | none; hoverable and clickable |
| `idle` (no notch) | opacity 0, not hit-testable | none |
| `hover` | notch + 8 × 4, top fillet 6, after a 120 ms dwell | one 2 pt `Ramp.blue[4]` pixel on the shelf under the notch |
| `listening` | wings: notch width + 112 × band, top 6, bottom 14 | target app icon 20 on the left; live 11-column pixel meter on the right |
| `handsFree` | wide wings: notch width + 168 × band, plus a 32 pt hint shelf while the hints are up, top 6, bottom 14 | target app icon + a 5-row lock mark on the left; live 15-column meter on the right; shelf: `fn / ⏎ Send`, `esc Cancel` |
| `meeting` | wings: notch width + 232 × band (clamped to the canvas), plus a 32 pt hint shelf while the hints are up, top 6, bottom 14 | brand pixel disc + elapsed `m:ss` on the left; the 24-column scrolling barcode on the right; shelf: `⌘ ×2 Save`, `esc Discard` |
| `processing` | same wings as the state it came from | target app icon on the left; three 2 pt cells stepping every 160 ms on the right |
| `landed` | same wings | icon on the left; a 5-row pixel check that develops left to right on the right |
| `undo` | card: 480 × band + 84, top 12, bottom 24 | target app icon (or `undo`), "Was that a mistake?", the digit, the partial transcript with an edge fade, Undo (primary, fixed 88), dismiss; meta line "You were 4 min 12 s in." and an 18-cell pixel drain |
| `notice` | same card | a kind-shaped pixel mark (spark, flame, tick, up arrow, dot) and "Superflow", a 10-cell drain, the notice title, its detail line, dismiss |
| `failed` | same card | "Not pasted." in the band (no icon; the band beside the notch is only ≈84 pt wide), transcript with an edge fade, Copy (primary, fixed 88), dismiss, "Paste blocked in <app>. ⌘V" |
| `recent` | same card | app icon and name, or mic and "Dictation", `Humanize.when` time, faded transcript, Copy, word count; empty row: "Hold fn and speak." |

When **Always show Island** is enabled, idle extends 5 pt below the hardware notch so the five-cell lamp is visible. Hover opens a 28 pt shelf with today's dictation words. Click opens the last five cleaned transcripts in a 480 × (band + 296) history panel: arrows move and scroll, Return copies, Space expands, Escape closes. Its rows constrain long previews so the close and copy controls remain visible. On an external display the idle mark sits on an opaque black pill.

**Live shelf.** `Show live text` adds a 40 pt shelf to dictation and meeting wings. Partials are secondary text; final phrases use primary text. Newest words align to a blue caret on the right, oldest words fade on the left; a speaker label is width constrained. The hints share the same shelf height while visible. Processing and pasted states never carry a stale live shelf. All live widths include the top flares when clamped to the canvas.

**Expanded meeting.** Click the meeting wings to open a 480 × (band + 168) panel with elapsed time, words, current speaker, an 88-cell largest-remainder talk-share bar, legend and optional live text. On a wide notch its recording mark stands alone rather than truncating the label. Close, Escape and outside click collapse to recording.

**Paste failed.** The 480 × (band + 148) card shows three cleaned lines with a bottom fade, target app, word count, Paste again and Copy. Copy closes this card after 0.9 s. It keeps focus in the target app and survives outside clicks.

Wing content hugs the outer edge at 14 (12 on the wide wings) and is centred on the band. A live mode says what the keys will do in pixels, not words: a lock for hands-free and the brand disc plus a clock for a meeting; the key hints are a 32 pt shelf that is part of the silhouette (the box grows by `IslandLayout.hintShelf`, so nothing is clipped and hit testing grows with it) and leaves after 2.4 s. `wingWidth` clamps to the canvas, so a wide notch on a narrow display can never push the silhouette off screen. The card is padded 20; band row `band`, gap 12, row 28, gap 8, meta 16, bottom 20 (`IslandLayout.cardHeight`). The band beside the notch is only ≈84 pt of usable width, so a failure spends it on "Not pasted." and a recent dictation spends it on the app icon plus name; never both. The dismiss target is 32 with a 16 pt glyph. `Copy` is a fixed 88 wide ("Copy" → "Copied" never reflows the transcript) and the only accent-filled element on the failure card; `Undo` is the only accent-filled element on the undo card.

**Gesture truth.** The gesture recogniser already owns push-to-talk, double-tap fn → `handsFree` (fn again or Return types it, Escape cancels) and right-⌘ double-tap → `meeting`. The Island now says which one is live instead of looking identical in all three, and `AppCoordinator+Input` sends the mode to the bridge only after the engine reports the session active.

**Accidental Escape.** Escape earns the undo card only when the recording has run at least 30 s (`IslandModel.undoMinimumSeconds`): the risk of losing a long dictation outweighs a card after a two-word slip. The card holds for 6 s, and the remaining time is drawn as an 18-cell pixel rail under the transcript that drains from the deadline — whole cells, one leaves every third of a second — with the digit in the band and a 10-cell version for notices. Reduce Motion keeps the cells static. The microphone is already closed, so Undo means "keep the words": it copies them and says `⌘V`, which is the one recovery that cannot lie about resuming. The meta line says how much was nearly lost ("You were 4 min 12 s in."): the card's own size argument. Escape plays `transcription-cancel` for a meeting as well as a dictation, and a cancelled meeting gets an honest notice ("Meeting stopped. / Nothing was saved.") because the engine deletes the take — there is no undo to offer.

**Notices.** Genuine milestones, streaks and user-requested model downloads come from the app's notifier. The view model never derives its own totals from pasted sessions. Passive notices queue behind recording, processing, the pasted tick and open cards; at most four wait. On rest the next notice grows out of the notch after 600 ms, and anything older than 120 s is discarded both on arrival and before display. Explicit refusal/status feedback can still explain a failed user action immediately. The mark is the kind: spark, flame, check, arrow or dot, developed in 200 ms. A milestone gets one dithered ring in 14 whole steps over 700 ms. Notices live 5 s, pause while hovered, and are absorbed back into the notch when dismissed.

**Pixel meter.** The fourth memorable element. 11 × 7 cells, cell 2, gap 1 (32 × 20), whole device pixels, `antialiased: false`. The model is one trail of levels, newest first, one entry per 33 ms frame. The newest level sits in the centre column and older levels spread outward, so the shape is a symmetric envelope radiating from the notch, not a bar chart scrolling sideways. The outer lit cell is the peak and carries `Ramp.blue[4]`, the interior `Ramp.blue[3]`, and a column with no level is one `Ramp.blue[2]` cell on the midline. Silence is therefore a visible blue dotted line, never a slab of near-black cells — the old meter drew silence in `controlPressed` and gated at five percent, which is why a quiet room looked like a dead meter. 30 Hz, attack 0.6, release 0.25, gate 0.04, quantised to whole cells; the model does not redraw when nothing changed. The ticker runs from the first frame of the session and resets on the next one, so every dictation opens on a clean line. `processing` swaps the meter for three stepping cells; the tail does not pretend to be live input. The meeting wing reads the same trail as a 24-column barcode: the newest column on the right is the white scan head, the next two stay blue 400 and the tail cools to blue 300 then navy, so a meeting reads as a tape you have been recording, not as a second dictation.

**Edge fade.** The transcript preview dissolves over its last 32 pt instead of ending in a clip or an ellipsis: an alpha mask on text, never a gradient fill. `EdgeFade` is the one file allowed to contain a `LinearGradient`.

**Motion.** Rest to open `smooth 0.44`; open to rest `smooth 0.32`; wings ↔ card `smooth 0.38`; rest ↔ rest and wings ↔ wings `snappy 0.20`; content in `smooth 0.30` delayed 0.10 (`Motion.islandIn`); content out `easeOut 0.10` (`Motion.islandOut`); blur 6 → 0, scale 0.94 → 1 anchored top. Nothing bounces, overshoots or loops. Reduce Motion makes the size instant and cross-dissolves content, no blur, no scale.

**Placement and focus.** The Island lives on the notch display at rest and hops to the focused display while working, only while idle, never animated. It is `.nonactivatingPanel`; `recent`, `history` and `meetingPanel` become key (so their keyboard controls work) and the failure card never takes focus. Outside clicks dismiss `recent` and `history` and collapse `meetingPanel`; the failure card survives them because the owner may click into the target field. Level is `mainMenu + 3`, collection behaviour `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `ignoresCycle`.

**Hit testing.** The canvas overlaps the menu bar and desktop, so `IslandHostingView.hitTest` uses the same `model.box` as the shell and checks the actual silhouette path, including its concave flares and rounded bottom. Transparent corners, the hidden external idle state, and all canvas space outside the silhouette remain click-through. `onHover` is attached to the shape, never the canvas.

**Timers.** Hover dwell 120 ms; landed 900 ms; failure timeout 12 s (4 s after the pointer leaves; disabled when transcripts are not stored, in which case the card stays until dismissed); copied 900 ms; undo 6 s and notice 5 s, both ticked once per second so their rails and the deadline agree.

**Accessibility.** VoiceOver announces "Listening", "Pasted" and "Couldn't paste. Transcript ready to copy." Haptics: `.alignment` on listening, `.levelChange` on landed, `.generic` on failure and on Copy. The idle notch is an accessibility button, "Show last dictation". Increase Contrast adds a 1 pt `Tok.contrastStroke` around the silhouette.

**Deleted.** The drag policy, the per-display persisted origin, the hardcoded 280 × 60 / 460 × 160 frames, the 22 / 26 radii, `IslandMetrics.topInset`, the legacy `showIdlePill` key (replaced by `island.alwaysOn`), and the stale `IslandDragPolicy.swift` reference. `StaleDefaults` removes `island.origin*`, `island.position*` and `showIdlePill` once at launch.

---

## 9. Dashboard

Source: `DashboardView.swift`, `DashboardLowerHalf.swift`, `DashboardCleanup.swift`, `ActivityYear.swift`.

- **Ledger:** one card, four equal `Metric` columns, 24 gap. One bare 14 pt symbol per metric, drawn in a fixed 16 × 16 box with a 6 pt gap to the 12 pt `text2` label, so the four values share one baseline. Value 28 / 400 tabular with `.numericText`. **Label and value only** — no note line: a third line under the number was a caption for a number that already says what it is, and the ledger reads in one pass without it. The session count is clamped at zero: `daily_stats.sessions` is a running counter that a delete can drive negative, so the ledger can never read "-1 sessions".
- **12-month graph:** `ActivityYear`. The year is **twelve small calendars**, not one wall: each month is its own block (weeks as columns, 7 rows), separated by an 8 pt gap with its own label, cells laid out at gap 3 on `Ramp.blue`. Days before the user's first dictation are **dust** (2 × 2 specks), days with history are cells, and **today is one `Tok.text` cell** — the caret where the next word lands. One `Metrics` value owns the geometry, so the canvas, the hit test and the labels cannot disagree. Hover does not open a tooltip: the line under the title becomes the readout and the number rolls. It reveals once per launch, right to left, in 14 whole steps over 600 ms.
- **Cleanup line:** left-aligned on the page's single left edge, one real 4 pt space between words, always.
- The old 53 × 7 `ContributionGrid` and its `levels` input are deleted; the ramp moved to `Ramp.blue`.
- **Latest dictation:** `LatestDictationCard` sits directly under the 12-month graph and is the only block that carries audio. Header: the `fn` keycap, the `You said` / `It typed` caption, the app icon, name and `Humanize.when` time, then `Replay` and a `Badge("Example")` before there is data. Body: `AudioPreview(url:chrome: .bare)` for the newest session's archived clip, then the cleanup line, so the picture of what the recognizer heard and what cleanup typed are one card. **The keycap is a control**: a click replays hold → release → clean, and it also goes down for real while the physical fn key is held (`DashboardViewModel.isFnHeld`, fed by `MenuBarController` from the hotkey stream). No audio is drawn when the archive has no clip for that session.
- **Lower half:** `AppsCard` (padding 8, 40 pt rows, real `NSWorkspace` icons) beside `HoursCard`, equal height via `fixedSize(vertical)`. Below the latest-dictation card.
  - **Where it lands.** Each row's share is a solid `accentSoft` block that ends in a two-column front of 4 pt cells, the column's density falling away from the solid (`ShareFront`, `cellHash` seed 11). It is the download card's fill in row form — real pixels, not a gradient — and every edge is snapped with `Pixel`.
  - **Your hours.** The day is cut into three 8-hour blocks with the same 12 pt gap the 12-month graph uses, and one label per block start (12 AM, 8 AM, 4 PM), so the shape of the working day is legible before reading a single label. Above it, a readout: `Peak hour` / the hovered hour at `metric`, and that hour's word count on the right edge. The readout is the tooltip; there is no floating label.
- **Audio component:** `AudioPreview`, `SpectroScrubber`, `ClipPlayer` and the spectrogram analysis live in `SuperflowUIComponents`, not in `FeatureHistory`. One implementation serves History and the dashboard, and no feature imports another feature.
- **Privacy:** "Don't store transcripts" means there is nothing to aggregate; the example state shows.

---

## 10. Onboarding

Four steps: welcome, permissions, models, done. Fixed 640 × 520, content column 480, footer 64, dots centred. No meetings step, no summary screen, no display-name field (it lives in Settings).

- Welcome: one display line at 40, the `fn` hero key at 48 × 32, the privacy sentence stated once. **The bloom is the one memorable element of the app.** Press and hold the key (click, or the real `fn` key while the app is frontmost — a *local* monitor, so no Input Monitoring permission): the keycap goes down 4 pt, the trackpad ticks, and a blue pixel bloom grows from under it in whole 8 pt cells, 14 steps over 800 ms, dithered at the edge and hollowed out around every text block. Release: it collapses back into the key in 450 ms, ticks again, and the sample line types itself from a white caret at 24 ms a character. Press again to replay. No loops, no idle animation. Reduce Motion: a static disc while held, the line appears whole.
- Permissions: "Four permissions." Four rows in one card — Microphone, Accessibility, Input Monitoring, and the Globe key. `Grant`, `Open Settings` and `Open Keyboard settings` are all neutral secondary buttons at 24, so Continue is the only accent control on the screen; rewards are `Badge("Granted")`; rows re-check on `didBecomeActive`. The skipped-permission note and the sidebar status footer are the same component, `StatusNote`: 40 tall, no fill and no radius at rest (a plate of `Tok.surface` read as a black hole in the glass sidebar) and a `wash` on hover, a 5 × 5 brand disc of 3 pt cells on the 13 pt line's cap height with a 10 pt gap, and, only while the state is genuinely indeterminate, a 4 × 2 scan rail under the label. The disc is `statusOK` green when ready, a dither in `text2` when the state is deterministic but not ready, and the ring is `statusBad` when a permission blocks the engine.
- Models: one `DownloadCard` per model fed by the same state as the Models page, with the same marks — the green NVIDIA eye for the speech model, the S1-mini plate for cleanup; errors as `NoticeBanner`. The cleanup row is **on by default**: its detail line reads "Cleans every dictation. On by default." and its switch is "Download S1-mini", so the default path fetches both models and no later step needs to ask again.
- Footer: **pinned, 64 tall on the 480 column**, so Back's glyph edge lands on x = 80 and the primary's right edge on x = 560 in the 640 window. The step content above it scrolls, so a tall step can never push the primary button out of the 520 pt window. Primary and "Set up later" play `click-soft`; Back plays `transcription-cancel`. Three equal-flex zones centre the dots at x = 320; "Set up later" sits 8 pt left of the primary. Quiet buttons pull their label flush with the column edge with a −12 leading inset, so the glyph edge, not the padding, aligns.
- Done: title ends in the pixel disc; `PracticeField` plus the shared `MicTestView`.
- The field is the backdrop for steps 1–3; step 4 runs ring collapse → disc grow → arc → land, all driven by state, never a timer. Reduce Motion renders the landed state.

---

## 11. Motion

Source: `Motion.swift`.

| Event | Animation |
|---|---|
| hover in | `easeOut 0.10` |
| hover out | `easeOut 0.22` |
| settle (fills, toasts, progress) | `timingCurve(0.23, 1, 0.32, 1) 0.28` |
| entrance stagger | `timingCurve(0.22, 1, 0.36, 1) 0.78`, 70 ms stagger |
| sidebar pill / segmented thumb / sidebar collapse | `smooth 0.30` |
| route / tab content | `easeOut 0.18` |
| menu open / close | `smooth 0.20` / `easeOut 0.12` |
| button hover in / out, press | `easeOut 0.10` / `easeOut 0.22`, press scale 0.98 (0.92 for controls 28 pt or smaller) |
| toggle | `snappy 0.22`; knob stretch `snappy 0.12` |
| readouts | `.numericText` with `snappy 0.15` |
| focus step | `easeOut 0.10` |
| menu highlight | `smooth 0.18` |
| stepper repeat | 380 ms, then 90 ms, then 45 ms after eight ticks |
| `ActivityYear` reveal | 14 whole steps over 600 ms, once per launch, right to left |
| `fn` bloom | 800 ms grow in 14 whole steps; 450 ms collapse; typed line 24 ms per character |
| Island rest → open | `smooth 0.44` size and radii; content `smooth 0.30` delayed 0.10 |
| Island open → rest | `smooth 0.32`; content leaves `easeOut 0.10` first |
| Island wings ↔ card | `smooth 0.38` |
| Island rest ↔ rest, wings ↔ wings | `snappy 0.20` |

Never linear, never ease-in-out, never `spring(` or `bouncy`. Nothing loops. Reduce Motion renders the end state and removes the waveform's animated target.

---

## 12. Pointer

Two modifiers in `Pointer.swift`: `clickable(_:)` (two layers — SwiftUI `pointerStyle(.link)` plus an AppKit cursor rect) and `scrubbable(_:)` (open hand at rest, closed hand while dragging). Every clickable control calls `clickable` internally and features do not manage cursors. `.pointerStyle` appears nowhere else. Disabled controls keep the arrow; text fields keep the I-beam; the graph is not clickable and does not change the pointer — it has a readout line, not a tooltip. The Island's idle notch and every card control are clickable (hand); everything else in the Island keeps the arrow.

---

## 13. Accessibility

- Every icon-only control has an accessibility label; list rows add `.isSelected`.
- Keyboard focus is `focusStep`: one `wash` fill step in the control's own shape (capsule, circle, or `rect(8)` for menu rows). **No outline is ever drawn** — not at rest, not on click, not on keyboard focus — because the macOS system ring is disabled at every window root with `.focusEffectDisabled()` and nothing takes first responder at launch.
- Increase Contrast is the one exception: it adds a 2 pt `Color.primary` ring in `FocusStep` and the shared `contrastStroke` to cards, fields, search, buttons and progress rows.
- Reduce Transparency falls back to `Tok.surface` behind glass.
- Reduce Motion renders final states: no pill slide, no disc flight, no waveform motion, no reveal offset.
- Text is selectable where it is the user's words; prose measure is capped at 720.
- The Island announces "Listening", "Pasted" and "Couldn't paste. Transcript ready to copy.", ticks a haptic on each edge, and exposes the idle notch as "Show last dictation". Its failure card never takes keyboard focus; the recent card does, so Escape works. Increase Contrast adds a 1 pt stroke around the silhouette; the Island is opaque, so Reduce Transparency has no effect on it.

---

## 14. Copy

Sentence case, verb-led, short. The privacy line is stated once in onboarding and once in Settings. No dotted meta chains, no trailing arrows, no exclamation marks, no ALL-CAPS eyebrows. Badges are status only. Buttons name the action. Empty states name the next action and its shortcut.

---

## 15. Enforcement and known gaps

Source: `tools/lint-forbidden`. It fails the build on: files over 400 lines; raw `Button`/`Toggle`/`Picker`/`Slider`/`Stepper`/`TextField`/`onTapGesture`/`NSCursor` in feature packages; `.pointerStyle` outside `Pointer.swift`; strokes outside `Surfaces.swift` / `Buttons.swift`; `Image(systemName:)` outside `Glyph.swift`; hex outside `DesignSystem` (canvas ramps excepted); weights above Medium; fixed sizes outside the table; `.animation(.linear/.easeInOut/.spring/.bouncy)`; third-party icon families; system split views/toolbars/searchable; `.popover`; `TimingSlider`; native `Slider` outside `AppSlider`; `isMovableByWindowBackground = true`; `.hierarchical`; `NSCursor` outside `Pointer.swift`; native `Menu`; `.focusable()` without `.focusEffectDisabled()`; icon sizes outside 9/12/14/16; `Divider()`.

Pass 3 adds: `focusRing(`; `.focusable(` without `.focusEffectDisabled(` in the same file; strokes outside `ContrastStroke` and `FocusStep`; `Picker`, `.pickerStyle(`, `Menu {`, `Menu(`, `.popover(` outside `UIComponents`; `ProgressRow`, `ContributionGrid(` as a view, `ContributionGrid.ramp`, `TimingSlider`; native `Slider(` outside `AppSlider`; an `AppButton` height other than 24, 28 or 32; `ClearKey`; `.pointerStyle` outside `clickable()` and `scrubbable()`; `Image("` outside `ModelMark`; `accentPressed` equal to `0x1E40AF`; an `AppSection` list without `.models`; raw font sizes outside `AppType`/`UIComponents`/`Icons`/SF Mono; `DateFormatter` in History; `AVAudioPlayer` outside `AudioPreview.swift`; `.sheet`/`.alert`/`.confirmationDialog`; `SettingRow("`; `help:` in Settings.

Pass 4 adds, in the Island's files: `visibleFrame`, `GlassSurface`, `.glassEffect(`, any `Material`; `DragGesture`, `.draggable(`, `isMovableByWindowBackground = true`; `setFrame(` and `NSWindow.Level(` outside `IslandPanelController.swift`; `showIdlePill` and the old persisted origin keys; `LinearGradient` outside `EdgeFade.swift`; a blur radius above 6; the deleted sizes and radii `280`, `460`, `22`, `26` as Island dimensions; and `default:` in the two files that switch on `IslandPhase`, so the compiler's exhaustiveness check stays meaningful.

Known gaps, recorded honestly:

- The UI face is unified through `AppType`; the lint rule for raw `.system(size:)` text passes. The bundled Albert Sans asset is still shipped for older builds but no view resolves through it.
- `NoticeBanner` is the app's inline error surface. Pass 3's `ContentUnavailableView` is not used because the app targets macOS 15 and the banner is the shared house style.
- The pixel field and disc are visual identity, not data; no screenshot verification has been completed for the motion timings.
- `safeAreaInset` is what shipped, not `safeAreaBar` (macOS 15 target). `scrollEdgeEffectStyle(.soft)` is applied only under macOS 26.
- The Island, menu-bar extra and command palette inherit the tokens but are outside the page-shell spec. The Island has its own section (§8.18).

---

## 16. Checks

Run from the repo root:

```
tools/lint-forbidden
swift build --package-path Packages/L4-UI/DesignSystem
swift build --package-path Packages/L4-UI/UIComponents
swift test  --package-path Packages/L4-UI/UIComponents
swift test  --package-path Packages/L3-Features/FeatureIsland
make test-fast
```

Mechanical expectations:

- `rg '\.system\(size:'` returns only the allowed type-table sizes; no UI face is `.custom(AppFont.baseName...)`.
- `rg 'monospaced\('` (font family) returns nothing; `.monospacedDigit()` may appear only on numbers.
- `rg 'Image\(systemName:'` returns only `Glyph.swift`.
- `rg 'Divider\(\)'` returns nothing.
- `rg '\.popover\(|NavigationSplitView|\.searchable\('` returns nothing.
- `rg '\.stroke|strokeBorder|\.border\('` returns only `Surfaces.swift` (focus/contrast) and `Buttons.swift` (button edge).
- `rg 'colorSchemeContrast'` covers every field/button surface.
- Every page title is `PixelStop(cells: 5, cell: 1.5)`; onboarding lands the same.
- `ActivityYear` derives its cell, pitch, height and label origins from one `Metrics` value built on the measured width, not `Space.pageMaxWidth`.
- Exactly one outline shape is drawn for navigation: `keyboardFocusRing` (2 pt accent, keyboard only). `FocusStep` adds the Increase Contrast edge.



# Superflow: Design Rebuild, Pass 3 (clarity, audio, structure)

> **Pass 4 note:** §6.4–6.6 (the transport player and the pixel-bar scrubber) are replaced by the pixel spectrogram described in §0.5. The archive writer in §6.1 and the tee in §6.2 stand unchanged.

**Audience:** the coding agent. **Status:** directive. Read all of it before touching a view.
**Relationship:** addendum to `DESIGN-REBUILD.md` and `DESIGN-REBUILD-2.md`. Where they conflict, **this file wins**, and you update `DESIGN.md` in the same change.
**Scope:** pixel law, focus ring, type tokens, History, audio preview, Shortcuts, Dictionary, dialogs, Settings controls and tabs.
**Out of scope:** the Island, onboarding, Meetings layout, `make verify` layer rules.
**One logic addition, and only one:** the audio archive in section 6. New L2 port, new adapter, a tee in the audio consumer, two nullable session columns. Everything else is skin and structure.

---

## 0. The Pixel Law (hardwire)

These ten rules outrank everything: taste, speed, brevity, your convenience, and any other line in this repo. If a rule below blocks you, stop and say so. Do not approximate silently.

1. **Pixel clarity is the product.** An edge that is half a pixel off is a bug, not a nit.
2. **Whole device pixels.** Every frame origin, size, offset, padding and radius lands on the 1/scale grid. No `.offset(x: 0.5)`. Any length derived from a `GeometryReader`, a ratio or a division goes through `Pixel.snap`. Symmetric shapes (bars, dots, thumbs, knobs) use `Pixel.snapEven` so they centre exactly.
3. **The 4pt grid, no exceptions:** 4, 8, 12, 16, 20, 24, 32, 48, 64. A number that is not on the list needs a written reason in the PR.
4. **One left edge.** Detail content starts at x = 32 from the sidebar edge. Labels share a column, trailing controls share a right edge, and the **glyph** (not its 32pt hit target) sits on the content edge.
5. **Text comes from `AppType` (section 4), nowhere else.** No `.font(.system(size:` outside `AppType` and `UIComponents`. Never scale text. Every changing number is tabular and its width is reserved, so nothing walks.
6. **Icons are bare SF Symbols** at 14, 16, 12 or 9, centred by their frame, never by padding. No enclosing variants.
7. **No strokes, no shadows, no gradients, no system focus ring.** The only ring is ours, drawn for keyboard navigation only (section 3).
8. **Motion is state-driven.** Springs only (`.snappy` small, `.smooth` large). Nothing bounces, nothing loops. Reduce Motion renders the end state.
9. **Verify by measuring, not by looking.** 2x screenshots, dark and light, then zoom to 400% on every edge you touched. `pixelAudit` (below) prints zero warnings. A screen is not done until the numbers in section 11 are measured and attached.
10. **Report honestly.** List what you could not verify. "Looks right" is not a result.

```swift
// UIComponents/Pixel.swift
enum Pixel {
    /// Snap a length to the device pixel grid.
    static func snap(_ v: CGFloat, _ scale: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
    /// Snap to an EVEN number of device pixels so symmetric shapes centre exactly on the grid.
    static func snapEven(_ v: CGFloat, _ scale: CGFloat) -> CGFloat { (v * scale / 2).rounded() * 2 / scale }
    static func isOnGrid(_ v: CGFloat, _ scale: CGFloat) -> Bool { abs(v * scale - (v * scale).rounded()) < 0.01 }
}

#if DEBUG
/// Prints a warning whenever the view's frame is off the device pixel grid.
/// Put it on Card, rows, controls, scrubber, dialog panel. It checks containers, not glyph baselines.
private struct PixelAudit: ViewModifier {
    let name: String
    @Environment(\.displayScale) private var scale
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(WindowSpace.name)) } action: { f in
            for (axis, v) in [("x", f.minX), ("y", f.minY), ("w", f.width), ("h", f.height)] where !Pixel.isOnGrid(v, scale) {
                print("PixelAudit \(name): \(axis) = \(v) is off the \(Int(scale))x grid")
            }
        }
    }
}
extension View { func pixelAudit(_ name: String) -> some View { modifier(PixelAudit(name: name)) } }
#else
extension View { func pixelAudit(_ name: String) -> some View { self } }
#endif
```

---

## 1. Defects in this round's screenshots (each one is a bug)

| # | Screen | What is wrong | Fixed in |
|---|---|---|---|
| G1 | History (Cleaned / Raw), Settings tab strip, Meetings (Live / Past meetings) | A blue ring around the whole segmented capsule. Not from our code. Probable cause (not proven): Full Keyboard Access is on, macOS hands the first key view focus when the window opens, and the container is focusable. | 3 |
| G2 | History list | Row title is a date ("Oct 28, 2026 at 03:01") and the time is printed again underneath. "0 words" rows are noise. | 5 |
| G3 | History | Copy and Delete sit in the window bar, 600pt from the session they act on. | 5 |
| G4 | History | You cannot play back your own recording. Nothing is kept. | 6 |
| G5 | Shortcuts | The top card is a generic add form: a "Say" field above a 160pt empty rectangle. It repeats the empty state's job and wastes the first screen. | 7, 8 |
| G6 | Dictionary | Same composer-card problem. | 7, 8 |
| G7 | Settings controls | Slider thumb draws grey (system). Toggles are generic. | 9 |
| G8 | Settings | Text weights and tracking are mixed. | 4 |
| G9 | Settings | Rows have no icons, so the page reads dry. | 9 |
| G10 | Settings, Text tab | 14 rows, a four-item profile list, three paragraph-length steppers, help sentences that pass 2 banned and that are still there, a Commands expander. No breathing room. | 9 |

---

## 2. Overrides to passes 1 and 2

| Topic | Before | Now |
|---|---|---|
| Focus ring | 2pt accent ring on keyboard focus, system ring "kept" | **System ring killed everywhere.** Our ring appears only after Tab or arrow keys, never after a click, never when the window opens. |
| Weights | Regular and Medium only | **350 for reading text, 500 for labels.** Reason: light text on dark reads heavier than it is, so 350 is optical compensation. Revert by changing one constant in `AppType`. |
| Tracking | Not specified | Per role, in `AppType`. |
| Slider | Apple's native `Slider` | **Custom `AppSlider` again.** The native thumb draws grey here (screenshot) and cannot be restyled. Blue 600 fill, `Tok.text` thumb. |
| Settings icons | None | **Every row has a bare 14pt SF Symbol in a fixed 20pt column.** Pass 2's D8 was inconsistency (one row had an icon); all rows having one fixes it. |
| Settings row height | 44 | 48 |
| History bar | Search + Copy + Delete | Search only. Copy and Delete move into the detail header. |
| Shortcuts / Dictionary | Search in the bar, composer row in the page | Scope toggle, then search row with Add, in the page body. Add opens a dialog. **The composer rows are deleted.** |
| Dialogs | `.sheet` banned, composer replaces it | **`DialogLayer`**, root overlay, solid `Tok.surface` panel over a flat scrim. `.sheet` stays banned. |
| Scope | Logic frozen | Audio archive added (section 6). |

Still binding: no strokes except Increase Contrast, blue 600 only, 4pt grid, `Reveal`, `Motion`, Reduce Motion and Reduce Transparency, one accent-filled element per view.

---

## 3. The blue ring (G1): kill it at four levels

Do all four. Report which one actually removed the ring.

```swift
// 1. Window level. WindowChrome configure, both .main and .onboarding:
window.contentView?.focusRingType = .none
DispatchQueue.main.async { window.makeFirstResponder(nil) }   // nothing starts focused, so nothing can draw a ring on open

// 2. Environment level. MainWindow and OnboardingView roots. Propagates to every descendant:
.focusEffectDisabled()

// 3. Component level. Segmented, AppButtonStyle, BarIconButton, Dropdown trigger, AppToggleStyle, AppSlider:
//    no .focusable() on a container unless it implements arrows AND draws our own indicator.
//    Every .focusable() in the codebase is followed by .focusEffectDisabled().

// 4. App launch:
InputModality.shared.start()
```

Our ring, keyboard only:

```swift
// UIComponents/InputModality.swift
@MainActor @Observable
final class InputModality {
    static let shared = InputModality()
    private(set) var isKeyboard = false
    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Tab (48), space (49), arrows (123...126) mean "navigating". Typing does not.
            let navigating = event.type == .keyDown && [48, 49, 123, 124, 125, 126].contains(event.keyCode)
            if navigating || event.type != .keyDown {
                MainActor.assumeIsolated { self?.isKeyboard = navigating }
            }
            return event
        }
    }
}

/// Apply INSIDE the focusable view (its label, or a ButtonStyle body), not on it.
/// `isFocused` reflects the nearest focusable ANCESTOR, so applying it on the view itself reads the wrong scope.
struct KeyboardFocusRing: ViewModifier {
    let radius: CGFloat
    @Environment(\.isFocused) private var focused
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Tok.accent, lineWidth: 2)
                .padding(-4)
                .opacity(focused && InputModality.shared.isKeyboard ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: focused)
                .allowsHitTesting(false)
        }
    }
}
extension View { func keyboardFocusRing(radius: CGFloat) -> some View { modifier(KeyboardFocusRing(radius: radius)) } }
```

This replaces pass 1's `focusRing(radius:active:)`. Delete the old one.

**Verify:** System Settings, Keyboard, Keyboard navigation **on**. Open every route and the dialogs. No ring on open, none after clicking. Press Tab: our ring appears on the first control, 2pt, accent, offset 2, and nothing else draws. Then turn it **off** and repeat. If the ring survives, report the view hierarchy (Debug View Hierarchy) instead of guessing.

---

## 4. Type tokens (G8)

Two weights. 350 for text you read, 500 for text you scan. Tracking is set per role, not per view.

```swift
// DesignSystem/AppType.swift
enum AppType {
    case caption     // 12 / 350
    case body        // 13 / 350
    case label       // 13 / 500
    case reading     // 15 / 350
    case title       // 15 / 500
    case metric      // 28 / 400, tabular

    private var size: CGFloat {
        switch self { case .caption: 12; case .body, .label: 13; case .reading, .title: 15; case .metric: 28 }
    }
    private var usesSystemFont: Bool { self == .label || self == .title || self == .metric }
    private var systemWeight: Font.Weight { self == .metric ? .regular : .medium }
    var tracking: CGFloat {
        switch self { case .caption: 0; case .body, .label: -0.1; case .reading, .title: -0.2; case .metric: -0.6 }
    }
    var font: Font {
        // 350 is between Light (-0.4) and Regular (0) on NSFont's weight scale. Approximate: check at 400% zoom.
        // Roles that need .monospacedDigit() stay on SwiftUI's own font; metric reads at 400, not 500.
        usesSystemFont ? .system(size: size, weight: systemWeight)
                       : Font(NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: -0.2)) as CTFont)
    }
}

extension View {
    func appType(_ role: AppType) -> some View { font(role.font).tracking(role.tracking) }
}
```

Rules: `metric` replaces the raw `.system(size: 28, weight: .medium)` in `Metric`, at weight **400**. Numeric text in 350 roles calls `.monospacedDigit()`; **verify it still tabularises on the `Font(NSFont)` path**. If it does not, move those roles to `.system(size:weight: .regular)` and report. SF Mono 12 and 13 (`design: .monospaced`) are the only fixed fonts allowed outside `AppType`.

---

## 5. History (G2, G3)

### 5.1 Say it like a person

One helper. No `Date.formatted(date: .abbreviated` or hand-built date strings anywhere in History. Locale decides 12 or 24 hour; never hardcode it.

```swift
// UIComponents/Humanize.swift
enum Humanize {
    /// "Just now", "12 min ago", "3:01 AM", "Yesterday, 11:42 PM", "Mon, 9:14 AM", "Oct 21", "Oct 21, 2025"
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let age = now.timeIntervalSince(date)
        if age < 45 { return "Just now" }
        if age < 3600 { return "\(max(1, Int(age / 60))) min ago" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        if daysAgo(date, now, calendar) < 7 { return "\(date.formatted(.dateTime.weekday(.abbreviated))), \(time)" }
        return date.formatted(calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year())
    }

    /// Sticky section headers: "Today", "Yesterday", "Monday", "Mon, Oct 21"
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if daysAgo(date, now, calendar) < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func words(_ n: Int) -> String { n == 1 ? "1 word" : "\(n.formatted()) words" }
    static func duration(_ s: TimeInterval) -> String {
        s < 60 ? "\(max(1, Int(s.rounded()))) sec" : "\(Int(s) / 60) min \(Int(s) % 60) sec"
    }
    /// Playback clock with tenths: "0:01.4"
    static func clock(_ t: TimeInterval) -> String {
        String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    private static func daysAgo(_ d: Date, _ now: Date, _ c: Calendar) -> Int {
        c.dateComponents([.day], from: c.startOfDay(for: d), to: c.startOfDay(for: now)).day ?? .max
    }
}
```

### 5.2 Row: the transcript is the title

56 tall, one line of text, one line of meta. The relative time re-renders every minute. A session with no speech is dimmed and shows no word count.

```swift
struct HistoryRow: View {
    let session: HistoryRowData        // names illustrative: appBundleID, preview, date, words
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                AppIcon(bundleID: session.appBundleID, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.words == 0 ? "No speech" : session.preview)
                        .appType(.label)
                        .foregroundStyle(session.words == 0 ? Tok.text2 : Tok.text)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        TimelineView(.everyMinute) { ctx in
                            Text(Humanize.when(session.date, now: ctx.date))
                        }
                        Spacer(minLength: 8)
                        if session.words > 0 { Text(Humanize.words(session.words)).monospacedDigit() }
                    }
                    .appType(.caption)
                    .foregroundStyle(Tok.text2)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(isSelected ? Tok.control : hover ? Tok.surface : .clear,
                        in: .rect(cornerRadius: Radius.nested, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.nested, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .clickable()
        .pixelAudit("HistoryRow")
    }
}
```

Section headers use `Humanize.day`, 12pt `caption`, `text2`, sticky.

### 5.3 Detail header: actions live next to the thing they act on

Layout, top to bottom: app icon, name, **Copy and Delete on the same row, right-aligned, horizontal**. Under the name: time, duration, word count as three separate elements, aligned under the name (indent 32 = icon 20 + gap 12). No middle dots. The window bar keeps the search field and nothing else.

```swift
struct HistoryDetailHeader: View {
    let session: HistoryDetailData     // appBundleID, appName, date, duration, words
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                AppIcon(bundleID: session.appBundleID, size: 20)
                Text(session.appName).appType(.title).foregroundStyle(Tok.text)
                Spacer(minLength: 16)
                HStack(spacing: 4) {
                    CopyButton(action: onCopy)
                    BarIconButton(glyph: .delete, label: "Delete session", action: onDelete)
                }
                // BarIconButton is a 32pt hit target around a 16pt glyph. Pull it out by 8
                // so the GLYPH, not the target, sits on the content edge (law 4).
                .padding(.trailing, -8)
            }
            .frame(height: 32)

            HStack(spacing: 12) {
                Text(Humanize.when(session.date))
                Text(Humanize.duration(session.duration))
                Text(Humanize.words(session.words)).monospacedDigit()
            }
            .appType(.caption)
            .foregroundStyle(Tok.text2)
            .padding(.leading, 32)
        }
    }
}

/// Copy confirms in place: the glyph morphs to a checkmark for 1.2 s (Apple's own symbol replace).
struct CopyButton: View {
    let action: () -> Void
    @State private var done = false
    var body: some View {
        BarIconButton(glyph: done ? .checkmark : .copy, label: "Copy transcript") {
            action()
            done = true
            Task { try? await Task.sleep(for: .seconds(1.2)); done = false }
        }
        .animation(.snappy(duration: 0.2), value: done)
    }
}
```

In `Icon`, add `.contentTransition(.symbolEffect(.replace))` so every glyph change morphs natively.

Detail order, top to bottom: header, `AudioPreview` (only if audio exists), `Segmented` Cleaned / Raw, transcript. It reads as the pipeline: what you said, what it heard, what it typed.

```swift
// HistoryView
SplitPage(title: "History") {
    SearchField(text: $vm.query, prompt: "Search transcripts", isFocused: $searchFocus)
} trailing: {
    EmptyView()                                   // Copy and Delete are gone from the bar
} list: { HistoryList(vm: vm).padding(.leading, 20) }
  detail: { HistoryDetail(vm: vm) }

// HistoryDetail, selected branch
ScrollView {
    VStack(alignment: .leading, spacing: 24) {
        HistoryDetailHeader(session: s, onCopy: vm.copySelected, onDelete: vm.deleteSelected)
        if let audio = vm.audio(for: s) { AudioPreview(audio: audio).id(s.id) }   // id: fresh player per session
        VStack(alignment: .leading, spacing: 16) {
            Segmented(selection: $mode, items: [.init(value: .cleaned, title: "Cleaned"), .init(value: .raw, title: "Raw")])
            TranscriptText(session: s, mode: mode)
        }
    }
    .padding(.horizontal, Layout.pad)
    .padding(.bottom, 48)
}
```

Delete keeps the undo toast. The audio file is only removed when the toast expires (section 6.4).

---

## 6. Audio preview (G4)

Settings already has **Keep audio journals**. **Read that code first.** If it already writes audio files somewhere, reuse them: skip 6.1 and 6.2 and feed 6.3 and 6.4 from what exists. If it does not, this is the writer.

### 6.0 Decisions (say so in the PR if you disagree)

- **Format:** AAC in `.m4a`, 16 kHz mono, 32 kbps. About 240 KB per minute. The same buffers that feed the recognizer are the ones written, so the clip is exactly what the model heard. That is the point: when History shows "I worn next", you can tell whether ASR or cleanup broke it.
- **Default on, 7-day retention.** A dictation tool whose output you cannot check against the source is flying blind. Retention is a Dropdown in Privacy (1 day, 7 days, 30 days).
- **Hard invariants:** "Don't store transcripts" on means **no audio is ever written**. Deleting a session deletes its file. Files live in Application Support, excluded from backup, and never leave the Mac. Dictation only; meetings are out of scope.
- **The waveform is precomputed.** Peaks are computed while writing (20 per second, one byte each) and stored on the session row. The player never decodes audio to draw.

### 6.1 Writer (L2 port, adapter implements it)

```swift
import AVFoundation

public struct ArchivedAudio: Equatable, Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let peaks: [UInt8]                  // 20 per second, 0...255
}

enum AudioStore {
    static let directory: URL = {
        var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Superflow/Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()
    static func url(for session: UUID) -> URL { directory.appendingPathComponent("\(session.uuidString).m4a") }
}

/// Fed from the audio CONSUMER task (the one that drains the ring buffer), never from the render callback.
/// `append` only copies and yields. Encoding and disk I/O happen on a utility task.
public final class AudioArchiveWriter: @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    private static let bucket = 800            // 50 ms at 16 kHz
    private let input: AsyncStream<[Float]>.Continuation
    private let work: Task<ArchivedAudio?, Never>

    public init(url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
                                   channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url,
                                   settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                              AVSampleRateKey: Self.sampleRate,
                                              AVNumberOfChannelsKey: 1,
                                              AVEncoderBitRateKey: 32_000],
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        input = continuation
        work = Task.detached(priority: .utility) {
            var peaks: [UInt8] = []
            var frames = 0, filled = 0
            var peak: Float = 0
            func closeBucket() {
                let level = WaveformEngine.normalized(rms: peak, floorDB: -54, ceilDB: -6)
                peaks.append(UInt8((level * 255).rounded()))
                peak = 0; filled = 0
            }
            for await chunk in stream {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.count)) else { continue }
                buffer.frameLength = AVAudioFrameCount(chunk.count)
                chunk.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: chunk.count) }
                do { try file.write(from: buffer) } catch { return nil }
                frames += chunk.count
                for s in chunk {
                    peak = max(peak, abs(s)); filled += 1
                    if filled == AudioArchiveWriter.bucket { closeBucket() }
                }
            }
            if filled > 0 { closeBucket() }
            file.close()                       // macOS 15+. If the SDK lacks it, delete this line: the file closes on scope exit.
            return ArchivedAudio(url: url, duration: Double(frames) / AudioArchiveWriter.sampleRate, peaks: peaks)
        }
    }

    public func append(_ samples: UnsafeBufferPointer<Float>) { input.yield(Array(samples)) }
    public func finish() async -> ArchivedAudio? { input.finish(); return await work.value }
    public func discard() async {
        input.finish()
        if let a = await work.value { try? FileManager.default.removeItem(at: a.url) }
    }
}
```

### 6.2 The tee (the only change in the engine path)

```swift
// Session start, in the code that already creates the waveform feed:
let archive: AudioArchiveWriter? = policy.keepAudio && !policy.dontStoreTranscripts
    ? try? AudioArchiveWriter(url: AudioStore.url(for: session.id)) : nil

// In the consumer loop, next to the recognizer feed and `engine.push(samples:)`:
buffer.withUnsafeBufferPointer { samples in
    engine.push(samples: samples)
    archive?.append(samples)
}

// Session end. Persist the two values on the session row (nullable columns audio_duration REAL, audio_peaks BLOB;
// names illustrative, map to the real schema, add nothing else):
let audio = await archive?.finish()
```

If a session produces zero words, call `archive?.discard()` instead.

### 6.3 Retention and deletion

- Delete session: tombstone the file; remove it when the undo toast expires. Undo restores the row and keeps the file.
- A sweep on launch and once a day removes files older than the retention setting and nulls both columns.
- Test: with "Don't store transcripts" on, run a dictation and assert the `Audio` directory is empty.

### 6.4 Player model (AVAudioPlayer, one source of time)

```swift
@MainActor @Observable
final class AudioPlayerModel {
    enum State { case idle, playing, paused }
    private(set) var state: State = .idle
    private(set) var duration: TimeInterval = 0
    private(set) var seeks = 0                              // bumps on every seek so a paused scrubber redraws
    var rate: Float = 1 { didSet { player?.rate = rate } }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let relay = EndRelay()

    /// Read once per frame by the scrubber. Deliberately not observed.
    var time: TimeInterval { player?.currentTime ?? 0 }

    func load(_ audio: ArchivedAudio) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: audio.url) else { return }
        p.enableRate = true
        p.delegate = relay
        relay.onEnd = { [weak self] in self?.state = .paused }
        p.prepareToPlay()
        player = p
        duration = p.duration
    }
    func play() {
        guard let p = player else { return }
        if p.currentTime >= p.duration - 0.02 { p.currentTime = 0 }
        p.rate = rate; p.play(); state = .playing
    }
    func pause() { player?.pause(); state = .paused }
    func toggle() { if state == .playing { pause() } else { play() } }
    func seek(_ t: TimeInterval) { player?.currentTime = min(max(t, 0), duration); seeks += 1 }
    func stop() { player?.stop(); player = nil; state = .idle }
}

private final class EndRelay: NSObject, AVAudioPlayerDelegate {
    var onEnd: (@MainActor () -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onEnd?() }
    }
}
```

### 6.5 The scrubber: a pixel scanner, not rounded bars

The Island draws soft rounded bars that flow outward. This is deliberately its opposite: square pixel cells (the 12-month graph's language), quantised, symmetric around a midline, with a **scan column** that turns the cells it passes from neutral to blue. No bars, no gradient, no glow.

- Cells about 4pt, gap 2, radius 1, 4 cells above and below the midline, 52pt tall. Column count follows the width; cell size is solved so columns end exactly on the right edge, snapped to device pixels.
- A resting column is one cell (a dot on the midline), the same idea as the Island's idle dot.
- Tone is a pure function of distance from the playhead, so there is no per-column state:
  ahead of it `Tok.controlPressed`, the head column `Tok.text`, the two columns behind it `ramp[4]`, everything older `Tok.accent`.
- Hover shows a ghost column in `ramp[4]` where a click would seek, and **the time readout is the tooltip** (same rule as Your hours): no floating label.
- Drag to scrub. Playback pauses while dragging and resumes on release.

```swift
struct PixelScrubber: View {
    let peaks: [UInt8]
    let model: AudioPlayerModel
    @Binding var hover: TimeInterval?
    var onTouch: () -> Void = {}                          // lets the card take keyboard focus (space, arrows)
    @Environment(\.displayScale) private var scale
    @State private var width: CGFloat = 0
    @State private var scrubbing = false
    @State private var resume = false

    static let half = 4
    static let gap: CGFloat = 2
    static let height: CGFloat = 52

    var body: some View {
        let _ = model.seeks                                    // dependency: redraw after a seek while paused
        TimelineView(.animation(paused: model.state != .playing && !scrubbing)) { _ in
            Canvas { ctx, size in draw(&ctx, size, played: model.time) }
        }
        .frame(height: Self.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !scrubbing { scrubbing = true; onTouch(); resume = model.state == .playing; if resume { model.pause() } }
                model.seek(time(at: g.location.x))
            }
            .onEnded { _ in scrubbing = false; if resume { model.play() } })
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): hover = time(at: p.x)
            case .ended: hover = nil
            }
        }
        .clickable()
        .accessibilityElement()
        .accessibilityLabel("Recording")
        .accessibilityValue(Humanize.clock(model.time))
        .accessibilityAdjustableAction { d in model.seek(model.time + (d == .increment ? 2 : -2)) }
        .pixelAudit("PixelScrubber")
    }

    private func time(at x: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1) * model.duration
    }

    private func level(at c: Int, of cols: Int) -> Double {
        let n = peaks.count
        if n >= cols {                                         // more peaks than columns: max-pool
            let lo = c * n / cols, hi = max(lo + 1, (c + 1) * n / cols)
            return Double(peaks[lo..<hi].max() ?? 0) / 255
        }
        let p = (Double(c) + 0.5) / Double(cols) * Double(n) - 0.5   // short clip: interpolate, never stretch into blocks
        let i = min(max(Int(p.rounded(.down)), 0), n - 1), j = min(i + 1, n - 1)
        let f = min(max(p - Double(i), 0), 1)
        return (Double(peaks[i]) * (1 - f) + Double(peaks[j]) * f) / 255
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, played: TimeInterval) {
        guard !peaks.isEmpty, model.duration > 0 else { return }
        let gap = Self.gap, half = Self.half
        let cols = max(1, Int((size.width + gap) / (4 + gap)))
        let cell = floor(((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)) * scale) / scale
        let pitch = cell + gap
        let stack = CGFloat(2 * half + 1) * cell + CGFloat(2 * half) * gap
        let top = Pixel.snap((size.height - stack) / 2, scale)
        let progress = played / model.duration
        let hoverCol = hover.map { Int($0 / model.duration * Double(cols)) }

        for c in 0..<cols {
            let lit = Int((level(at: c, of: cols) * Double(half)).rounded())
            let behind = (progress - (Double(c) + 0.5) / Double(cols)) * Double(cols)   // < 0: ahead of the playhead
            let tone: Color =
                c == hoverCol ? ContributionGrid.ramp[4]
                : behind < 0  ? Tok.controlPressed
                : behind < 1  ? Tok.text
                : behind < 3  ? ContributionGrid.ramp[4]
                :               Tok.accent
            let x = Pixel.snap(CGFloat(c) * pitch, scale)
            for r in -lit...lit {
                let y = Pixel.snap(top + CGFloat(half + r) * pitch, scale)
                ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: cell, height: cell), cornerRadius: 1, style: .continuous),
                         with: .color(tone))
            }
        }
    }
}
```

### 6.6 The card

Bare play and pause glyph (Apple's symbol replace morph), the readout, a rate button. Space plays and pauses, left and right seek 2 s, once the card has focus (clicking the scrubber or play takes it). No ring, since `focusEffectDisabled` is on.

```swift
struct AudioPreview: View {
    let audio: ArchivedAudio
    @State private var model = AudioPlayerModel()
    @State private var hover: TimeInterval?
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                PixelScrubber(peaks: audio.peaks, model: model, hover: $hover, onTouch: { focused = true })
                HStack(spacing: 8) {
                    BarIconButton(glyph: model.state == .playing ? .pause : .play,
                                  label: model.state == .playing ? "Pause" : "Play") { focused = true; model.toggle() }
                    TimeReadout(model: model, hover: hover)
                    Spacer(minLength: 16)
                    RateButton(rate: Binding(get: { model.rate }, set: { model.rate = $0 }))
                }
            }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { model.toggle(); return .handled }
        .onKeyPress(.leftArrow) { model.seek(model.time - 2); return .handled }
        .onKeyPress(.rightArrow) { model.seek(model.time + 2); return .handled }
        .onAppear { model.load(audio) }
        .onDisappear { model.stop() }
        .pixelAudit("AudioPreview")
    }
}

private struct TimeReadout: View {
    let model: AudioPlayerModel
    let hover: TimeInterval?
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: model.state != .playing)) { _ in
            HStack(spacing: 8) {
                Text(Humanize.clock(hover ?? model.time)).foregroundStyle(Tok.text)
                Text(Humanize.clock(model.duration)).foregroundStyle(Tok.text2)
            }
            .appType(.label).monospacedDigit()
        }
    }
}

private struct RateButton: View {
    @Binding var rate: Float
    var body: some View {
        AppButton(title: rate == 1 ? "1×" : rate == 1.5 ? "1.5×" : "2×", kind: .quiet, height: 28) {
            rate = rate == 1 ? 1.5 : rate == 1.5 ? 2 : 1
        }
        .frame(width: 48)                                       // fixed width: the label changes, the layout does not
    }
}
```

Add glyphs `play = "play.fill"` and `pause = "pause.fill"`.

Not built, deliberately: word-by-word highlight during playback. It needs per-token timestamps from the recognizer. If FluidAudio exposes them, that is the next feature, and the scrubber already has the playhead to drive it.

---

## 7. Shortcuts and Dictionary (G5, G6)

**Delete the composer cards.** The "Say [ ] ... empty rectangle" card on Shortcuts and the "You say / You get" card on Dictionary are gone. Adding happens in a dialog (section 8). The empty state stays exactly as it is: the pixel stop is the one thing on these pages that already works.

Skeleton, top to bottom, all on the canvas, all starting at x = 32:

```
Shortcuts.●
[ Personal | Shared ]                              <- Segmented, on the canvas
[ search ........................ ]   [ ⋯ ] [ + Add shortcut ]    <- 16 below the toggle
(list, or the empty state)
```

- Toggle, then search row, **16 apart** (one group). Title to toggle and search row to list are 32 (between groups).
- Right side of the search row: the menu slot, then **Add** (accent, 32 tall). Add is the one accent-filled element on the page. ⌘N does the same thing.
- **The slot left of Add is the Import / Export `ActionMenu`.** The owner asked for a history or refresh icon there. Refresh on local data does nothing, and pass 2 deleted it for that reason, so the slot is given a real job instead. Swapping to `BarIconButton(.refresh, ...)` is one line if the owner insists.
- The window bar on these two pages is empty (drag area only). Search moved into the body. History, Meetings and Settings keep search in the bar.
- **Scopes:** `Personal | Shared`, as asked. Be aware in the PR that Superflow has no sharing backend and Settings says everything stays on this Mac, so the Shared tab is an honest empty state until that exists. The toggle hides itself when `scopes.count == 1`, so removing Shared is deleting one enum case.

```swift
struct ListControls<Scope: Hashable>: View {
    @Binding var scope: Scope
    let scopes: [Segmented<Scope>.Item]
    @Binding var query: String
    let prompt: String
    @Binding var searchFocus: Bool
    let addTitle: String
    let menu: [ActionMenu.Action]
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if scopes.count > 1 { Segmented(selection: $scope, items: scopes) }
            HStack(spacing: 12) {
                SearchField(text: $query, prompt: prompt, isFocused: $searchFocus)
                Spacer(minLength: 16)
                ActionMenu(actions: menu)
                AppButton(title: addTitle, kind: .primary, height: 32, glyph: .add, action: onAdd)
            }
        }
    }
}

enum EntryScope: Hashable {
    case personal, shared
    static let items: [Segmented<EntryScope>.Item] =
        [.init(value: .personal, title: "Personal"), .init(value: .shared, title: "Shared")]
}

struct ShortcutsView: View {
    @Bindable var vm: ShortcutsViewModel
    @Environment(DialogHost.self) private var dialogs
    @State private var scope: EntryScope = .personal
    @State private var searchFocus = false

    var body: some View {
        Page(title: "Shortcuts") {
            ListControls(scope: $scope, scopes: EntryScope.items,
                         query: $vm.query, prompt: "Search shortcuts", searchFocus: $searchFocus,
                         addTitle: "Add shortcut",
                         menu: [.init(title: "Import…", run: vm.importEntries), .init(title: "Export…", run: vm.exportEntries)],
                         onAdd: add)
            if scope == .shared {
                EmptyState(title: "Nothing shared yet.", message: "Shared shortcuts appear here.")
                    .frame(minHeight: 320)
            } else if vm.rows.isEmpty {
                EmptyState(title: "Nothing here yet.", message: "Press ⌘N to add a phrase.")
                    .frame(minHeight: 320)
            } else {
                ShortcutList(vm: vm)
            }
        }
        .searchShortcut($searchFocus)
        .background {
            Button("Add shortcut", action: add)
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func add() {
        dialogs.present { AddShortcutDialog { phrase, text in vm.add(phrase: phrase, text: text) } }
    }
}
```

Dictionary uses the identical skeleton: `Page(title: "Dictionary")`, `ListControls` with "Search terms" and "Add term", the same menu. Below the list, keep the **Try it** playground card (Personal scope only).

List rows are not hover-only. The Willow screenshot reveals edit and trash icons on hover; do not copy that, it is invisible to keyboard and VoiceOver users.

- Row: 36 tall, the pass 1 `EntryRow` (trigger in `text2`, arrow glyph, result in `text` Medium).
- Click a row opens the same dialog pre-filled (Edit). Delete is ⌫ and the context menu. A disabled entry is `text2`.
- Two columns when the pane is wide enough: `LazyVGrid(columns: [.init(.flexible(), spacing: 16), .init(.flexible())], spacing: 4)`. No pills, no borders, no card per entry. Group headers (Terms, Corrections) in 12pt `text2`.
- The Willow screenshots show the skeleton to copy. Their UI (bordered pills, grey dialog buttons, stock tabs) is the generic thing this rebuild exists to avoid. Take the structure, not the surface.

---

## 8. Dialogs (replaces the composer rows)

One layer at the window root, above `MenuLayer`. Solid `Tok.surface` panel (forms need the surface and well ladder, which glass breaks), flat scrim, 480 wide, padding 24, radius 16, fields 32 tall with radius 8. Opens with a 0.97 scale, a 6pt rise and a fade (`menuIn`); closes with a 120 ms fade. Esc cancels, ⌘Return confirms, the first field is focused on open.

```swift
// Tok.scrim, in DesignSystem: Color(light: .init(hex: 0x000000, alpha: 0.28), dark: .init(hex: 0x000000, alpha: 0.55))

@MainActor @Observable
final class DialogHost {
    struct Presented: Identifiable { let id = UUID(); let content: AnyView }
    private(set) var presented: Presented?
    func present<V: View>(@ViewBuilder _ content: () -> V) { presented = .init(content: AnyView(content())) }
    func dismiss() { presented = nil }
}

struct DialogLayer: View {
    @Environment(DialogHost.self) private var host
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            if let p = host.presented {
                ZStack {
                    Tok.scrim.contentShape(.rect).onTapGesture { host.dismiss() }
                    p.content
                        .scaleEffect(shown || reduceMotion ? 1 : 0.97)
                        .offset(y: shown || reduceMotion ? 0 : 6)
                        .opacity(shown || reduceMotion ? 1 : 0)
                }
                .id(p.id)
                .transition(.opacity)
                .onAppear { withAnimation(Motion.menuIn) { shown = true } }
                .onDisappear { shown = false }
            }
        }
        .animation(Motion.menuOut, value: host.presented?.id)
    }
}

// MainWindow: @State private var dialogHost = DialogHost()
//   .overlay { MenuLayer() }
//   .overlay { DialogLayer() }          // above menus
//   .environment(dialogHost)

struct DialogFrame<Content: View>: View {
    let title: String
    let confirmTitle: String
    let canConfirm: Bool
    var showsCancel = true
    let onConfirm: () -> Void
    @ViewBuilder var content: Content
    @Environment(DialogHost.self) private var host

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).appType(.title).foregroundStyle(Tok.text)
            content
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if showsCancel {
                    AppButton(title: "Cancel", kind: .quiet, height: 32) { host.dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                AppButton(title: confirmTitle, kind: .primary, height: 32) { onConfirm(); host.dismiss() }
                    .disabled(!canConfirm)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .modifier(ContrastStroke(radius: Radius.card))
        .pixelAudit("DialogFrame")
    }
}

struct DialogField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).appType(.caption).foregroundStyle(Tok.text2)
            content
        }
    }
}

/// Single line. Plain, 32 tall, 8 radius, `well` on a surface, one fill step on hover and focus. Caret is the focus indicator.
struct AppTextField: View {
    @Binding var text: String
    let prompt: String
    var mono = false
    var autofocus = false
    @FocusState private var focus: Bool
    @State private var hover = false

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Tok.text2))
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 13, design: .monospaced) : AppType.body.font)
            .foregroundStyle(Tok.text)
            .tint(Tok.accent)
            .focused($focus)
            .focusEffectDisabled()
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(focus || hover ? Tok.bg : Tok.well, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: focus || hover)
            .task { if autofocus { focus = true } }
    }
}

/// Multi-line, SF Mono 12. Same recipe as AppTextField.
struct AppEditor: View {
    @Binding var text: String
    let prompt: String
    var minHeight: CGFloat = 128
    @FocusState private var focus: Bool

    var body: some View {
        let mono = Font.system(size: 12, design: .monospaced)
        TextEditor(text: $text)
            .font(mono)
            .scrollContentBackground(.hidden)
            .focused($focus)
            .focusEffectDisabled()
            .padding(8)
            .frame(minHeight: minHeight)
            .background(focus ? Tok.bg : Tok.well, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .overlay(alignment: .topLeading) {
                // TextEditor insets its text by about 5pt. Tune the two paddings until the placeholder's
                // first glyph sits exactly where the caret will be (measure it, law 9).
                if text.isEmpty {
                    Text(prompt).font(mono).foregroundStyle(Tok.text2)
                        .padding(.leading, 13).padding(.top, 8).allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.15), value: focus)
    }
}

struct AddShortcutDialog: View {
    let onAdd: (_ phrase: String, _ text: String) -> Void
    @State private var phrase = ""
    @State private var text = ""

    var body: some View {
        DialogFrame(title: "Add a shortcut", confirmTitle: "Add shortcut",
                    canConfirm: !phrase.trimmingCharacters(in: .whitespaces).isEmpty && !text.isEmpty,
                    onConfirm: { onAdd(phrase.trimmingCharacters(in: .whitespaces), text) }) {
            VStack(alignment: .leading, spacing: 16) {
                DialogField("You say") { AppTextField(text: $phrase, prompt: "sign off", autofocus: true) }
                DialogField("It types") { AppEditor(text: $text, prompt: "Best, Harshit") }
            }
        }
    }
}

struct AddTermDialog: View {
    enum Kind: Hashable { case term, correction }
    let onAddTerm: (String) -> Void
    let onAddCorrection: (_ say: String, _ get: String) -> Void
    @State private var kind: Kind = .term
    @State private var say = ""
    @State private var result = ""

    var body: some View {
        DialogFrame(title: kind == .term ? "Add a term" : "Add a correction", confirmTitle: "Add",
                    canConfirm: !say.isEmpty && (kind == .term || !result.isEmpty),
                    onConfirm: { kind == .term ? onAddTerm(say) : onAddCorrection(say, result) }) {
            VStack(alignment: .leading, spacing: 16) {
                Segmented(selection: $kind, items: [.init(value: .term, title: "Term"), .init(value: .correction, title: "Correction")], onCard: true)
                DialogField(kind == .term ? "Term" : "You say") { AppTextField(text: $say, prompt: kind == .term ? "Next.js" : "next js", autofocus: true) }
                if kind == .correction {
                    DialogField("You get") { AppTextField(text: $result, prompt: "Next.js") }.transition(.opacity)
                }
            }
            .animation(Motion.fade, value: kind)
        }
    }
}
```

If the trigger is a common English phrase, show the pass 1 `Badge("Common phrase")` inline under the "You say" field. Present with `dialogs.present { AddShortcutDialog { ... } }`. Edit reuses the same dialogs with initial values.

---

## 9. Settings (G7, G8, G9, G10)

### 9.1 What stays, what goes (this is the owner's call, delegated to you; do exactly this)

Cut from the UI. The view-model properties stay and keep their defaults, so no logic changes.

| Cut | Why |
|---|---|
| Context profile (Writing, Chat, Code, Prompting) and its help sentence | The owner does not want it. It was also the cluttered block. |
| Cleanup context dropdown | Belongs to the same bundle. |
| "Turn on Code Speak to preview." and "Reads identifiers, paths and flags…" | Help text. Pass 2 banned it. |
| Minimum block, Preferred maximum, Hard maximum (three steppers) | Replaced by one **Block length** dropdown: Short 15/25/35, Standard 25/35/45, Long 40/60/80. The Standard row is today's values. The Short and Long numbers are placeholders; the owner tunes them. |
| Commands expander inside the Code Speak card | Becomes a quiet **Commands** button that opens a dialog. |

| Tab | Rows after the cut |
|---|---|
| General | Name, Appearance, Launch at login, Idle pill |
| Dictation | Speech model, Clean up with S1-mini. Card 2: Hold to talk, Double-tap window, Meeting hold |
| Text | Card 1: Spell out 0 to 9, Capitalize sentences, End with a period, Trailing space. Card 2: Paragraph break (Segmented), Block length. Card 3: Code Speak |
| Meetings | Meetings in stats, Speaker separation |
| Privacy | Don't store transcripts, **Keep audio** (renamed from Keep audio journals), **Delete audio after** (new, section 6), Delete transcripts, Diagnostics, Licenses |
| Advanced | Typing speed (moved here), Interactive deadline, Background deadline, Cleanup workers |

Breathing room: rows 48 tall, **24 between cards**, at most three cards per tab, at most five rows per card. The Segmented tab strip carries no ring (section 3).

### 9.2 Row with a bare icon in a fixed column

```swift
struct SettingRow<Control: View>: View {
    let glyph: Glyph
    let title: String
    @ViewBuilder var control: Control
    init(_ glyph: Glyph, _ title: String, @ViewBuilder control: () -> Control) {
        self.glyph = glyph; self.title = title; self.control = control()
    }
    var body: some View {
        GridRow {
            HStack(spacing: 12) {
                Icon(glyph: glyph, size: 14).frame(width: 20, height: 20)      // same column for every row
                Text(title).appType(.label)
            }
            .foregroundStyle(Tok.text)                                         // icon and label identical, never text2
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            control.frame(minHeight: 48).gridColumnAlignment(.trailing)
        }
    }
}
```

Glyphs to add to the `Glyph` enum (SF Symbols, **none verified**, `validateGlyphs()` will catch a miss; if a symbol encloses itself, pick the plain variant):

| Row | Symbol | Row | Symbol |
|---|---|---|---|
| Name | `person` | Spell out 0 to 9 | `number` |
| Appearance | `circle.lefthalf.filled` | Capitalize sentences | `textformat.size.larger` |
| Launch at login | `power` | End with a period | `text.append` |
| Idle pill | `capsule` | Trailing space | `space` |
| Speech model | `waveform` | Paragraph break | `paragraphsign` |
| Clean up | `textformat` | Block length | `text.alignleft` |
| Hold to talk | `hand.tap` | Code Speak | `chevron.left.forwardslash.chevron.right` |
| Double-tap window | `timer` | Meetings in stats | `chart.bar` |
| Meeting hold | `person.2` | Speaker separation | `person.2` |
| Don't store transcripts | `eye.slash` | Keep audio | `waveform` |
| Delete audio after | `clock` | Delete transcripts | `trash` |
| Diagnostics | `doc.text.magnifyingglass` | Licenses | `doc.text` |
| Typing speed | `keyboard` | Deadlines | `hourglass` |
| Cleanup workers | `cpu` | | |

### 9.3 Toggle: 40 x 24, Blue 600 on, white knob, smooth

Knob 20 at rest, inset 2. While pressed it stretches to 26 (state feedback, the right edge holds on the on side). A trackpad haptic fires on flip. Reduce Motion renders the end state. Hit area 32.

```swift
struct AppToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } label: { Color.clear.frame(width: 40, height: 32) }
        .buttonStyle(SwitchFace(isOn: configuration.isOn))
        .focusEffectDisabled()
        .clickable()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct SwitchFace: ButtonStyle {
    let isOn: Bool
    func makeBody(configuration: Configuration) -> some View { Face(isOn: isOn, pressed: configuration.isPressed) }

    private struct Face: View {
        let isOn: Bool
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hover = false

        var body: some View {
            let knob: CGFloat = pressed ? 26 : 20
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? (hover ? Tok.accentHover : Tok.accent) : Tok.controlPressed)
                    .frame(width: 40, height: 24)
                Capsule().fill(.white)                       // white in both modes: it always sits on the track
                    .frame(width: knob, height: 20)
                    .offset(x: isOn ? 40 - 2 - knob : 2)
                    .keyboardFocusRing(radius: 12)
            }
            .frame(width: 40, height: 32)
            .contentShape(.rect)
            .opacity(enabled ? 1 : 0.4)
            .animation(reduce ? nil : .snappy(duration: 0.22), value: isOn)
            .animation(reduce ? nil : .snappy(duration: 0.12), value: pressed)
            .animation(.easeOut(duration: 0.10), value: hover)
            .onHover { hover = $0 }
            .pixelAudit("Toggle")
        }
    }
}
```

The ring here sits on the knob for lack of a better anchor; if it looks wrong, apply it to the 40 x 24 track instead. Check light mode: off-track `controlPressed` (#DADADA) against a white knob is low contrast. If it fails the eye test, darken the off-track for light mode only and say so.

### 9.4 Slider: 4pt track, Blue 600 fill, `Tok.text` thumb

Track 4, thumb 16 (18 while dragging). The thumb follows the pointer **continuously**; the value snaps to the step underneath, and on release the thumb settles onto the step with `.snappy(0.18)`. That is what makes it feel smooth instead of notched. The thumb is `Tok.text` (white in dark, near-black in light) so it never vanishes on a white card. Fixed 280 wide, readout 64, so every track in Settings starts on the same x.

```swift
struct AppSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 50
    let unit: String

    @Environment(\.displayScale) private var scale
    @Environment(\.isEnabled) private var enabled
    @State private var raw: Double?                       // pointer-true value while dragging, nil at rest
    private let thumb: CGFloat = 16, track: CGFloat = 4

    var body: some View {
        HStack(spacing: 16) {
            GeometryReader { geo in
                let usable = geo.size.width - thumb
                let span = range.upperBound - range.lowerBound
                let x = Pixel.snap(usable * CGFloat(((raw ?? value) - range.lowerBound) / span), scale)
                ZStack(alignment: .leading) {
                    Capsule().fill(Tok.controlPressed).frame(height: track)
                    Capsule().fill(Tok.accent).frame(width: x + thumb / 2, height: track)
                    Circle().fill(Tok.text)
                        .frame(width: thumb, height: thumb)
                        .scaleEffect(raw != nil ? 1.125 : 1)             // 18pt, whole pixels
                        .keyboardFocusRing(radius: 11)
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let t = min(max((g.location.x - thumb / 2) / usable, 0), 1)
                        let v = range.lowerBound + Double(t) * span
                        raw = v
                        value = min(max((v / step).rounded() * step, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in withAnimation(.snappy(duration: 0.18)) { raw = nil } })
                .focusable().focusEffectDisabled()
                .onKeyPress(.leftArrow)  { value = max(range.lowerBound, value - step); return .handled }
                .onKeyPress(.rightArrow) { value = min(range.upperBound, value + step); return .handled }
            }
            .frame(height: 32)
            .clickable(enabled)

            Text("\(Int(value)) \(unit)")
                .appType(.body).monospacedDigit().foregroundStyle(Tok.text2)
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.15), value: value)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: 280)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityRepresentation { Slider(value: $value, in: range, step: step) }   // the one allowed `Slider(`: VoiceOver only
        .pixelAudit("AppSlider")
    }
}
```

Delete `TimingSlider`. Lint now bans `Slider(` everywhere except this file.

### 9.5 Code Speak: a card that shows what it does

When off, it is one row. When on, the card grows (`.smooth(0.30)`) to reveal a live try-it: type a phrase, see what Code Speak types. No help sentences. The result crossfades as you type. **Commands** opens a dialog with the reference list instead of an in-card expander.

```swift
struct CodeSpeakCard: View {
    @Bindable var vm: SettingsViewModel
    @Environment(DialogHost.self) private var dialogs
    @State private var sample = "camel case user profile id"

    var body: some View {
        Card(padding: 8) {
            VStack(spacing: 0) {
                Grid { SettingRow(.code, "Code Speak") { AppToggle(label: "Code Speak", isOn: $vm.codeSpeak) } }
                    .padding(.horizontal, 12)
                if vm.codeSpeak {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("You say").appType(.caption).foregroundStyle(Tok.text2)
                            Spacer()
                            AppButton(title: "Commands", kind: .quiet, height: 24) {
                                dialogs.present { CodeSpeakCommandsDialog(commands: vm.codeSpeakCommands) }
                            }
                        }
                        AppTextField(text: $sample, prompt: "camel case user profile id", mono: true)
                        Text("It types").appType(.caption).foregroundStyle(Tok.text2)
                        let typed = vm.codeSpeakPreview(sample)         // the existing preview function; names illustrative
                        Text(typed.isEmpty ? " " : typed)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Tok.text)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .id(typed)
                            .transition(.opacity)
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
                    .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.30), value: vm.codeSpeak)
        .animation(.easeOut(duration: 0.15), value: vm.codeSpeakPreview(sample))
    }
}

struct CodeSpeakCommandsDialog: View {
    let commands: [(say: String, types: String)]
    var body: some View {
        DialogFrame(title: "Code Speak commands", confirmTitle: "Done", canConfirm: true, showsCancel: false, onConfirm: {}) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.offset) { _, c in
                        HStack(spacing: 16) {
                            Text(c.say).foregroundStyle(Tok.text2).frame(width: 180, alignment: .leading)
                            Icon(glyph: .arrow, size: 12).foregroundStyle(Tok.text2)
                            Text(c.types).foregroundStyle(Tok.text)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .frame(height: 32)
                    }
                }
            }
            .frame(height: 256)
        }
    }
}
```

### 9.6 Text tab, assembled

```swift
struct TextTab: View {
    @Bindable var vm: SettingsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard {
                SettingRow(.numbers, "Spell out 0 to 9")   { AppToggle(label: "Spell out 0 to 9", isOn: $vm.numbersAsWords) }
                SettingRow(.capitalize, "Capitalize sentences") { AppToggle(label: "Capitalize sentences", isOn: $vm.capitalizeSentences) }
                SettingRow(.period, "End with a period")   { AppToggle(label: "End with a period", isOn: $vm.finalPeriod) }
                SettingRow(.space, "Trailing space")       { AppToggle(label: "Trailing space", isOn: $vm.trailingSpace) }
            }
            SettingsCard {
                SettingRow(.paragraph, "Paragraph break") {
                    Segmented(selection: $vm.blockSeparator,
                              items: [.init(value: .blankLine, title: "Blank line"), .init(value: .newline, title: "New line")],
                              onCard: true)
                }
                SettingRow(.blocks, "Block length") {
                    Dropdown(selection: $vm.blockLength, options: BlockLength.allCases.map { .init(value: $0, title: $0.title) })
                }
            }
            CodeSpeakCard(vm: vm)
        }
    }
}

enum BlockLength: CaseIterable {
    case short, standard, long
    var title: String { switch self { case .short: "Short"; case .standard: "Standard"; case .long: "Long" } }
    var values: (min: Int, preferred: Int, hard: Int) {
        switch self { case .short: (15, 25, 35); case .standard: (25, 35, 45); case .long: (40, 60, 80) }
    }
}
extension SettingsViewModel {          // maps onto the three existing properties; names illustrative
    var blockLength: BlockLength {
        get { BlockLength.allCases.first { $0.values == (minBlock, preferredBlock, hardBlock) } ?? .standard }
        set { (minBlock, preferredBlock, hardBlock) = newValue.values }
    }
}
```

Dictation, Privacy and Advanced follow the same pattern from the table in 9.1. Sliders use `AppSlider`, toggles `AppToggle`, and every row passes a glyph.

---

## 10. Lint (extend `tools/lint-forbidden`)

Fail the build on all of passes 1 and 2, and also on:

- `.focusable(` in a file with no `.focusEffectDisabled(`; `focusRing(radius:active:)` anywhere (replaced by `keyboardFocusRing`)
- `NSEvent.addLocalMonitorForEvents` outside `InputModality`
- `.font(.system(size:` outside `AppType` and `UIComponents`, except `design: .monospaced`
- `.formatted(date:` or `DateFormatter` inside `FeatureHistory` (use `Humanize`)
- `AVAudioPlayer` outside `AudioPreview.swift`; `AVAudioFile(forWriting` outside `AudioArchiveWriter` (pass 4: the spectrogram card owns the only player)
- `.sheet(`, `.popover(`, `.alert(`, `.confirmationDialog(` anywhere (dialogs use `DialogHost`)
- `Slider(` outside `AppSlider`; `TimingSlider` anywhere
- `SettingRow(` without a glyph argument
- `help:` anywhere in Settings
- raw `Text("...").foregroundStyle(Tok.text2)` is fine; a raw `Color.white` outside `AppToggleStyle` is not

---

## 11. Acceptance

### 11.1 Measure these on 2x crops, dark and light, and attach the numbers

| Item | Value |
|---|---|
| Left edge of title, toggle, search field, list rows, dialog-less content | x = 220 + 32 = 252 on every page |
| History row | 56 tall, icon 20, gap 12, title 13/500, meta 12/350 |
| History detail header | row 32 tall, icon 20, gap 12; Copy and Delete 32pt targets, 4 apart; **glyph right edge = pane right minus 32** |
| Meta row under the name | indent 32, three elements 12 apart |
| Audio card | padding 20, 8-band spectrogram, cell about 4, gap 2, last column ends exactly on the content edge; transport row 32 |
| Shortcuts / Dictionary | toggle to search row 16, title to toggle 32, Add 32 tall, accent-filled, the only one on the page |
| Dialog | 480 wide, padding 24, radius 16, fields 32 tall, radius 8, field gap 16, footer buttons 32 |
| Toggle | track 40 x 24, knob 20 (26 pressed), inset 2 |
| Slider | track 4, thumb 16 (18 dragging), cell 280, readout 64, all tracks share one left edge |
| Settings row | 48 tall, icon column 20, gap 12, cards 24 apart |

### 11.2 Checklist

- [ ] No blue ring anywhere, with Keyboard navigation on **and** off. After Tab, only our 2pt ring appears.
- [ ] The window opens with nothing focused.
- [ ] History rows lead with the transcript. No date as a title. "No speech" rows are dimmed and carry no word count.
- [ ] "12 min ago" updates without reloading. A 24-hour locale shows 24-hour times.
- [ ] Copy and Delete sit on the right of the detail header, horizontal, and the glyph edge aligns to the content edge. Copy morphs to a checkmark for 1.2 s.
- [ ] A dictation made with Keep audio on has a player. One made with "Don't store transcripts" on writes **no file**.
- [ ] Scrubber: scan column visible while playing, seek by click and drag, hover ghost column, readout shows the hovered time, space and arrows work after clicking the card. Static and correct under Reduce Motion.
- [ ] Deleting a session removes its audio when the undo toast expires. Retention sweep removes old files.
- [ ] The Shortcuts top card and the Dictionary composer are gone. Toggle, search row, Add, dialog. Empty state unchanged.
- [ ] Dialog opens with a scale, rise and fade, first field focused, Esc cancels, ⌘Return confirms, Add disabled until valid.
- [ ] Settings: no help text, every row has an icon in the same column, Context profile and the three block steppers are gone, Code Speak card expands and shows a live result.
- [ ] Toggle and slider match 9.3 and 9.4 in both modes. The slider thumb is visible on a white card in light mode.
- [ ] Only weights 350 and 500, tracking from `AppType`, numbers tabular.
- [ ] `pixelAudit` prints nothing on any route.
- [ ] Hand cursor on every clickable thing in this pass (scrubber, play, rate, dialog buttons, rows, toggle, slider track), arrow on disabled, I-beam in fields.
- [ ] `make verify` green, lint in, `DESIGN.md` rewritten, PR lists everything in section 12.
- [ ] Swap-the-logo test passes on every screen.

---

## 12. Not verified by the author of this file

Say each of these in your report, and what you found.

- Nothing here has been compiled. Fix compile errors, do not work around the design.
- **The ring's cause is a hypothesis** (Full Keyboard Access plus a focusable container). The four-level fix covers the plausible causes; report which one worked.
- `Font(NSFont as CTFont)` for weight 350, and whether `.monospacedDigit()` still tabularises on it.
- `AVAudioFile.close()` (macOS 15+), AAC at 16 kHz mono and 32 kbps (check the file plays and sounds acceptable), and `AsyncStream.makeStream`.
- `onGeometryChange`, `onContinuousHover`, `NSHapticFeedbackManager.perform(.alignment, performanceTime: .now)`, `contentTransition(.symbolEffect(.replace))`.
- Every new SF Symbol name in 9.2.
- `TextEditor` placeholder padding in `AppEditor`.
- All schema, view-model and port names. They are illustrative. Map them to the real ones and do not change the schema beyond the two nullable audio columns.
- "Keep audio journals" may already write audio. Read it before building 6.1.
- Strict concurrency may object to `AVAudioFile` and `AVAudioFormat` crossing into the detached task.


# Superflow: Ground-Up Design Rebuild

**Audience:** the coding agent. **Status:** directive. Read all of it before touching a view.
**Scope:** main window (Dashboard, History, Dictionary, Shortcuts, Meetings, Settings), onboarding, and every shared component in L4 (`DesignSystem`, `UIComponents`, `Icons`). The Island inherits the new tokens and nothing else; do not change its behavior.
**Out of scope:** logic. View models, engines, ports, layer rules and `make verify` stay exactly as they are. This is a skin-and-skeleton rebuild, not a refactor.

---

## 1. Mandate

The current UI is rated minus 10 out of 10 by its owner. It is not "almost there". It looks clean in the way a template looks clean: dry, generic, and interchangeable with any other dark SaaS app. Delete it and rebuild from tokens up. Do not patch.

### 1.1 What is wrong (observed in the screenshots; each item is a bug)

1. **Titlebar band is lighter than the canvas** (about `#333` against `#0A0A0A`) on every screen, including onboarding. The top of the window must be the same color as the page. It must read as one surface.
2. **Strokes everywhere.** Cards, search field, segmented controls, badges, the practice field, the permissions list, the text field, even the progress track. The owner said it plainly: no borders. Background steps are enough.
3. **Progress is a full-width blue bar** under the header. This is the most generic progress pattern there is.
4. **Boxed icons.** "Open Settings" has an arrow inside a square. Icons come from a mixed set, some enclosed in circles, some bare. Every icon must be bare and from one family: Apple's.
5. **Stat tiles carry a colored dot, an icon and a label** in the same header line. Three signals for one fact.
6. **Every empty state is the same stack:** icon, bold title, grey sentence, pill button. The pill duplicates the primary action already in the header.
7. **Every page header is the same stack:** title, subtitle, a right-aligned cluster of three buttons (Import, Export, Add), then a search field, then a segmented filter. The skeleton is identical on four pages, so none of them has a point of view.
8. **Footnotes with an info icon** at the bottom of pages. The same privacy sentence is repeated on four screens.
9. **Onboarding is 8 steps.** Meetings, a summary screen and a display-name field are in there. It should be 4.
10. **Windows are too wide and buttons are over-padded**, with a leading chevron inside "Continue" and a check inside "Finish". The icons carry no information.
11. **Meta strings chained with middle dots** ("Qwen3 0.6B fine-tune · Q4_K_M GGUF · on-device via llama.cpp"). Template chrome.
12. **No pointer cursor** on clickable things.
13. The display italic in the screenshots looks like a system serif fallback, not Exposure Italic. Verify the font actually loads (see 5.6).

### 1.2 What stays

The product structure (sidebar plus six pages), the four dictation stats, the 12-month graph, two-pane history, blue 600 as the only brand color, and the pixel full stop from `DESIGN.md` section 8 as the identity.

### 1.3 Boldness budget

Spend it in one place: **the pixel full stop.** It is already the signature in `DESIGN.md`. Every page title ends in it, every empty state is built on it, the onboarding backdrop is the pixel field that collapses into it. Everything else is quiet, dark and disciplined. If a screen has a second memorable element, delete one of them.

---

## 2. Precedence

`DESIGN.md` is the base. Stay aligned with it. Where it conflicts with this document, **this document wins**, and you rewrite `DESIGN.md` in the same change (its own header requires that).

| Topic | `DESIGN.md` / build plan said | Now |
|---|---|---|
| Strokes | §1.5, §6: card = fill + 1pt hairline | **No strokes anywhere.** Only allowed: 2pt accent focus ring, and 1pt stroke when Increase Contrast is on |
| Badge edge | §4.1 inset shade strokes | **Deleted.** Badges are tinted fill + colored text only |
| Dark card | `#141414` | `#171717` (neutral 900). Full ladder in 5.1 |
| Light canvas | `#FFFFFF` | `#F4F4F4`, cards `#FFFFFF`. Without borders, white on white has no hierarchy |
| Light `text.2` | `#737373` | `#666666` (4.3:1 on the new canvas is not enough) |
| Icons | §2: SF Symbols. Build plan §18.2: Hugeicons only | **SF Symbols only.** Hugeicons, Phosphor and any custom icon set are removed. Build plan §18.2 is superseded |
| Pointer cursor | Build plan §18.3: balanced `NSCursor` push/pop | `.pointerStyle(.link)` (target is macOS 26, so no manual cursor code) |
| Onboarding CTA | 40pt | 32pt. Control heights are 24 / 28 / 32 |
| Window | min 960 x 640 | default 960 x 620, min 880 x 560. Onboarding is a fixed 640 x 520 |
| Sidebar | 240 (220 to 320) | 220 (200 to 280) |
| Type | six roles | add **Metric**: SF Pro 28 Regular, tabular. Nothing else is added |
| Onboarding | 8 steps incl. meetings, summary | 4 steps (section 8) |

Still binding from `DESIGN.md`: two layers (glass navigation over solid content), glass is system-made, no glow, no gradients, no shadows on content, Regular and Medium weights only, 4pt grid, concentric radii, reduce motion and reduce transparency, and every item in its §12 checklist that does not mention borders.

---

## 3. Process (mandatory, in this order)

1. **Write the token list you will use** (spacing, radii, type roles, colors, control heights) as a comment block at the top of the first PR. Use only those.
2. **Rewrite `DESIGN.md`** with the table above applied.
3. Build foundations (section 5), then components (section 6), then the shell and pages (section 7), then onboarding (section 8).
4. **Screenshot every route, dark and light, at 2x.** Run the checklist in section 10. Fix before reporting done.
5. **Delete anything that does not carry information or afford an action.** Then delete one more thing.
6. `make verify` stays green. Add the lint rules in section 9.

Swap-the-logo test: if a screen could belong to any other dictation app, redesign it.

---

## 4. Rules

Every rule is checkable. If you cannot point to a token or a number for a visual decision, do not make it.

**R1. Anti-slop.** Reject on sight:
- strokes or borders on anything (R2)
- a colored dot plus an icon plus a label in one header
- an icon inside a circle, square or rounded box
- a full-width progress bar; any gradient, glow or shimmer
- the empty-state stack of icon, title, sentence, pill button
- the page-header stack of title, subtitle, three buttons, search field, segmented filter
- info-icon footnotes, and the same sentence repeated across screens
- middle-dot chains in meta text; `→` or `>` appended to button or link labels; leading chevrons inside buttons
- numbered markers where the content is not a sequence; ALL CAPS eyebrow labels
- icons added "for balance". If an icon does not carry meaning, remove it

**R2. No borders.** Layers are separated by background luminance only. Dark mode is very dark and the steps are small and deliberate. The full ladder is in 5.1. Exceptions, exhaustively: the 2pt accent focus ring on keyboard focus, and a 1pt stroke when `colorSchemeContrast == .increased`. There are no hairline dividers either; spacing and hover fills do that job.

**R3. Icons are Apple's, and they are bare.** SF Symbols only, regular weight, hierarchical or monochrome rendering, one size per context (14 in rows, 16 in toolbars, 12 in buttons, 9 for the dropdown chevron). No enclosing variants (`.circle`, `.square`, `.rectangle`, badges). Icons live in one `Glyph` enum (5.4). Icon-only controls have an accessibility label. One exception: vendor marks, see 8.4.

**R4. Color.** Blue 600 is the only accent and appears on the primary action, the active state, the focus ring and the graph ramp, nothing else. Status hues exist only inside badges. Dark canvas is `#0A0A0A`. Light is neutral, not warm and not tinted. `text.3` is removed from the app.

**R5. Type.** SF Pro for everything. Exposure Italic only for page titles (28), empty-state titles (28) and onboarding titles (40). Weights Regular and Medium. Every changing number is tabular. Sentence case. Prose measure at most 720pt.

**R6. Space.** 4pt grid: 4, 8, 12, 16, 24, 32, 48, 64. Page padding 32. Section gap 32. Card padding 20. Space inside a group is always smaller than space between groups. Radii: capsule for buttons and toggles, 16 cards, 12 nested panels, 8 fields and badges, 6 code chips. Nested radius is outer minus padding.

**R7. Motion explains, it does not decorate.** Curves and durations are in 5.2. Nothing bounces. Nothing loops. Entrance stagger runs only in onboarding and on the Dashboard's first appearance after launch. Route changes are an opacity cross-fade and nothing else. Reduce Motion renders the final state.

**R8. Pointer.** Everything clickable shows the pointing hand through one modifier (5.3). Text inputs keep the I-beam. Disabled controls keep the arrow. Lint enforces it.

**R9. Native glass and blur, and only on the navigation layer.** Glass: sidebar, toolbar, popovers (dropdowns), sheets, toasts, the command palette, the Island. Never glass on cards, rows, lists, badges, in-content buttons or behind long text. No glass on glass. No hand-rolled blur, no tinted material. `.blur(radius:)` is a transition effect of 6pt or less.

**R10. Structure is information.** Each page has one job and one skeleton chosen for that job (section 7). Search and filters live in the toolbar, not in the page body. Import and Export live in an overflow menu. The single primary action lives in the toolbar. Empty states say what to do in one sentence and never repeat the toolbar action as a button.

**Copy.** Sentence case, verb-led, short. State the privacy line once (onboarding step 1) and once more in Settings, never elsewhere. The greeting uses a name only if the user set one: "Good evening." not "Still up, You?". Meta text is separate elements (a time on the right, a count in tabular numerals), not a dotted string.

---

## 5. Foundations (copy these, then adjust numbers, not structure)

### 5.1 Tokens

Replaces `Tok` from `DESIGN.md` §11.1. Keep `Color(hex:)` and `Color(light:dark:)` as they are.

```swift
import SwiftUI
import AppKit

enum Tok {
    // Surface ladder. Luminance steps only, never a stroke.
    static let bg             = Color(light: .init(hex: 0xF4F4F4), dark: .init(hex: 0x0A0A0A)) // canvas, titlebar, toolbar
    static let surface        = Color(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x171717)) // cards, hovered list rows
    static let well           = Color(light: .init(hex: 0xEDEDED), dark: .init(hex: 0x0F0F0F)) // inset: fields and tracks inside a card
    static let control        = Color(light: .init(hex: 0xEBEBEB), dark: .init(hex: 0x1F1F1F)) // buttons, selected row
    static let controlHover   = Color(light: .init(hex: 0xE3E3E3), dark: .init(hex: 0x262626))
    static let controlPressed = Color(light: .init(hex: 0xDADADA), dark: .init(hex: 0x2E2E2E))

    // Text. Two levels. text.3 is gone.
    static let text  = Color(light: .init(hex: 0x0A0A0A), dark: .init(hex: 0xFAFAFA))
    static let text2 = Color(light: .init(hex: 0x666666), dark: .init(hex: 0xA3A3A3))

    // Accent, blue 600.
    static let accent        = Color(hex: 0x2563EB)
    static let accentHover   = Color(light: .init(hex: 0x1D4ED8), dark: .init(hex: 0x3B82F6))
    static let accentPressed = Color(hex: 0x1E40AF)
    static let accentText    = Color(light: .init(hex: 0x2563EB), dark: .init(hex: 0x60A5FA))
    static let accentSoft    = Color(light: .init(hex: 0xDBEAFE), dark: .init(hex: 0x2563EB, alpha: 0.17))
}

enum Radius {
    static let card: CGFloat = 16, nested: CGFloat = 12, field: CGFloat = 8, chip: CGFloat = 6
}

/// The only stroke besides the focus ring. Appears only with Increase Contrast.
struct ContrastStroke: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

extension View {
    /// Keyboard focus ring. 2pt, accent, offset 2. System controls keep the system ring.
    func focusRing(radius: CGFloat, active: Bool) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Tok.accent, lineWidth: 2)
                .padding(-4)
                .opacity(active ? 1 : 0)
        }
    }
}
```

Dark ladder in plain sight: `0A` canvas, `0F` well, `17` surface, `1F` control, `26` hover, `2E` pressed. Each step is about 4 to 8 luminance points. If a step is invisible on a real display, adjust the number, do not add a stroke.

### 5.2 Motion

```swift
enum Motion {
    static let hoverIn  = Animation.easeOut(duration: 0.10)
    static let hoverOut = Animation.easeOut(duration: 0.22)           // return is slower than entry
    static let settle   = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
    static let enter    = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.78)
    static let stagger: Double = 0.07
    // Springs: .snappy for small, .smooth for large. No other springs. Never linear or ease-in-out.
}

/// Onboarding and first Dashboard appearance only.
struct Reveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 8)
            .blur(radius: shown || reduce ? 0 : 4)
            .onAppear {
                guard !reduce else { return }
                withAnimation(Motion.enter.delay(Double(index) * Motion.stagger)) { shown = true }
            }
    }
}
extension View { func reveal(_ index: Int) -> some View { modifier(Reveal(index: index)) } }
```

Required motion, all driven by real state and nothing else:
- Press: `scaleEffect(0.98)` on buttons.
- Sidebar selection and segmented thumb **slide** between items using `matchedGeometryEffect` with `.smooth`.
- Numbers use `.contentTransition(.numericText())` so a stat rolls instead of swapping.
- The 12-month graph appears once in whole stepped reveals (the §8.8 pattern: radial, jittered, 14 steps, 600ms), then is static.
- Toasts rise 8pt and fade over `settle`.
- The `fn` keycap physically presses when the user actually holds Fn (observe the session state stream through an L2 protocol, never import the adapter).

### 5.3 Pointer cursor

```swift
extension View {
    /// Pointing hand for anything clickable. Disabled passes false and gets the arrow.
    func clickable(_ enabled: Bool = true) -> some View {
        pointerStyle(enabled ? .link : nil)
    }
}
```

Applies to: buttons, sidebar rows, segmented items, toggles, dropdown triggers and rows, clickable list rows, graph cells that show a tooltip, links, keycaps that are interactive. Does not apply to: text fields, plain labels, disabled controls. Every interactive component in `UIComponents` calls it internally, so features get it free.

### 5.4 Icons: Apple native only

```swift
enum Glyph: String, CaseIterable {
    // Sidebar. Specific, open Apple symbols rather than the stock pick for each concept.
    case dashboard = "chart.xyaxis.line", history = "text.line.first.and.arrowtriangle.forward"
    case dictionary = "character.book.closed", shortcuts = "command"
    case meetings = "person.2.wave.2", settings = "slider.horizontal.3", models = "memorychip"
    // Actions and state
    case search = "magnifyingglass", add = "plus", more = "ellipsis", copy = "doc.on.doc", delete = "trash"
    case refresh = "arrow.clockwise", importIn = "arrow.down.to.line", exportOut = "arrow.up.to.line"
    case checkmark = "checkmark", chevronUpDown = "chevron.up.chevron.down", arrow = "arrow.right"
    // Subjects
    case mic = "mic", accessibility = "accessibility", keyboard = "keyboard", speaker = "speaker.wave.2"
    case waveform = "waveform", cleanup = "textformat"
}

struct Icon: View {
    let glyph: Glyph
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    var body: some View {
        Image(systemName: glyph.rawValue)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.hierarchical)
            .accessibilityHidden(true)
    }
}

#if DEBUG
/// Call once at launch. A missing name fails loudly instead of rendering nothing.
func validateGlyphs() {
    for g in Glyph.allCases {
        assert(NSImage(systemSymbolName: g.rawValue, accessibilityDescription: nil) != nil,
               "Missing SF Symbol: \(g.rawValue)")
    }
}
#endif
```

I have not verified every symbol name against the SF Symbols app. `validateGlyphs()` catches missing names; open SF Symbols and fix them. If a symbol draws its own circle, square or badge, choose the unenclosed variant. If two symbols fit, pick the one with fewer strokes.

Removed from the UI entirely: the info-circle footnote icon, the colored stat dots, the stat-tile icons, the leading chevron in "Continue", the check in "Finish", the box-arrow on "Open Settings" (it becomes a quiet text button with no icon), the Recheck button (permissions re-check on `didBecomeActive`).

### 5.5 Window chrome (fixes the light titlebar)

```swift
final class ChromeView: NSView {
    var configure: (@MainActor (NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { configure?(window) }
    }
}

struct WindowChrome: NSViewRepresentable {
    enum Kind { case main, onboarding }
    let kind: Kind

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        let kind = kind
        view.configure = { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            if kind == .onboarding {
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.setContentSize(NSSize(width: 640, height: 520))
            } else {
                window.minSize = NSSize(width: 880, height: 560)
            }
        }
        return view
    }
    func updateNSView(_ view: ChromeView, context: Context) {}
}
```

On every root view: `.containerBackground(Tok.bg, for: .window)`, `.toolbar(removing: .title)`, `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`, `.background(WindowChrome(kind: ...))`. On scroll views: `.scrollEdgeEffectStyle(.soft, for: .top)` so content dissolves under the toolbar instead of cutting off. Screenshot the result and confirm the top 52pt is the same color as the page in both modes. Traffic lights float on the canvas.

### 5.6 Display font

```swift
enum AppFont {
    /// Replace with the real PostScript name of the bundled Exposure Italic (check NSFontManager.shared.availableFonts).
    static let displayName = "Exposure-Italic"
    static func display(_ size: CGFloat) -> Font { .custom(displayName, size: size) }
}
#if DEBUG
func validateDisplayFont() {
    assert(NSFont(name: AppFont.displayName, size: 28) != nil,
           "Exposure Italic is not registered. Check ATSApplicationFontsPath and the target membership.")
}
#endif
```

Display 40: tracking -2, line 0.96. Display S 28: tracking -1.4, line 0.98. Never upright, never below 28.

### 5.7 The pixel full stop and the pixel field

This is the brand. Implement it once, in `UIComponents`, and reuse it.

```swift
// Deterministic per-cell hash in 0...1.
func cellHash(_ i: Int, _ j: Int, _ seed: UInt32) -> CGFloat {
    var h = UInt32(truncatingIfNeeded: i) &* 374761393
        &+ UInt32(truncatingIfNeeded: j) &* 668265263
        &+ seed &* 2246822519
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return CGFloat(h) / CGFloat(UInt32.max)
}

func vnoise(_ x: CGFloat, _ y: CGFloat, _ s: UInt32) -> CGFloat {
    let xi = Int(floor(x)), yi = Int(floor(y))
    let fx = x - floor(x), fy = y - floor(y)
    let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
    let a = cellHash(xi, yi, s), b = cellHash(xi + 1, yi, s)
    let c = cellHash(xi, yi + 1, s), d = cellHash(xi + 1, yi + 1, s)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
}

func fbm(_ x: CGFloat, _ y: CGFloat, _ s: UInt32) -> CGFloat {
    0.6 * vnoise(x, y, s) + 0.3 * vnoise(x * 2, y * 2, s) + 0.1 * vnoise(x * 4, y * 4, s)
}

/// DESIGN.md §8.3. Five bands collapsed to three tones. nil means "deep": draw nothing, the page shows through.
enum Tone {
    static let g: [CGFloat] = [0.42, 0.49, 0.55, 0.61]
    static func color(_ v: CGFloat, _ i: Int, _ j: Int, dark: Bool) -> Color? {
        let mid  = dark ? Color(hex: 0x1E3A8A) : Color(hex: 0x93C5FD)
        let pale = Color(hex: 0x2563EB)
        let even = (i + j) % 2 == 0
        switch g.firstIndex(where: { v < $0 }) ?? 4 {
        case 0:  return nil
        case 1:  return even ? mid : nil
        case 2:  return mid
        case 3:  return even ? pale : mid
        default: return pale
        }
    }
}

/// DESIGN.md §8.7. Odd N: 5 hero, 7 compact, 11 default. Snapped to device pixels.
struct PixelStop: View {
    var cells = 5
    var cell: CGFloat = 1.5
    var seed: UInt32 = 11
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme

    private var unit: CGFloat { max(1 / scale, (cell * scale).rounded() / scale) }

    var body: some View {
        let u = unit, n = cells, dark = scheme == .dark
        Canvas { ctx, _ in
            let c = CGFloat(n) / 2
            for j in 0..<n {
                for i in 0..<n {
                    let dx = CGFloat(i) + 0.5 - c, dy = CGFloat(j) + 0.5 - c
                    let r = (dx * dx + dy * dy).squareRoot()
                    guard r <= c else { continue }
                    let t = r / c
                    var v = 0.80 - 0.22 * t * t + (cellHash(i, j, seed) - 0.5) * 0.12
                    if t < 0.75, cellHash(i, j, seed &+ 5) < 0.16 { v -= 0.17 }   // speckle, never on the rim
                    guard let color = Tone.color(v, i, j, dark: dark) else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(i) * u, y: CGFloat(j) * u, width: u, height: u)),
                             with: .color(color), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: CGFloat(n) * u, height: CGFloat(n) * u)
        .accessibilityHidden(true)
    }
}
```

`PixelField` below is the SwiftUI `Canvas` version, allowed by `DESIGN.md` §8.1 for surfaces up to 40 x 40 cells. The onboarding window is 40 x 33 cells, so it qualifies. It implements noise, tone map, organic text hole and stepped reveal. You still implement §8.6 (collapse ring) and §8.7 (disc travelling to its slot) on top of it for the final onboarding step.

```swift
struct PixelField: View {
    var clear: [CGRect] = []        // text frames in this view's space; unioned into one hole
    var cell: CGFloat = 16
    var cover: CGFloat = 0.42       // lower than the 0.5 default: sparser field
    var seed: UInt32 = 11
    var reveal: CGFloat = 1         // 0...1, stepped
    var drift: Double = 120         // seconds per pass, 0 = static
    var steps = 14
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let still = reduceMotion || drift == 0 || phase != .active
        let dark = scheme == .dark
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { tl in
            let t = still ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                Self.draw(&ctx, size, t: t, clear: clear, cell: cell, cover: cover, seed: seed,
                          reveal: reveal, drift: drift, steps: steps, dark: dark)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, clear: [CGRect],
                             cell: CGFloat, cover: CGFloat, seed: UInt32, reveal: CGFloat,
                             drift: Double, steps: Int, dark: Bool) {
        let cols = Int((size.width / cell).rounded(.up)), rows = Int((size.height / cell).rounded(.up))
        guard cols > 0, rows > 0 else { return }
        let h = 2.4 / CGFloat(cols)
        let shift = drift > 0 ? Int((sin(t * 2 * .pi / drift) * Double(cols) / 6).rounded()) : 0
        // Hole = each frame grown by padX 5, padY 3 cells (DESIGN.md §8.5).
        let holes = clear.map { r in
            (cx: r.midX / cell, cy: r.midY / cell, hx: r.width / 2 / cell + 5, hy: r.height / 2 / cell + 3)
        }
        let eased = 1 - pow(1 - reveal, 3)
        let cutoff = (eased * CGFloat(steps)).rounded(.up) / CGFloat(steps)

        for j in 0..<rows {
            for i in 0..<cols {
                let px = CGFloat(i) + 0.5, py = CGFloat(j) + 0.5
                // Reveal: radial from center, jittered per cell, in whole steps.
                let gx = (px - CGFloat(cols) / 2) / (CGFloat(cols) / 2)
                let gy = (py - CGFloat(rows) / 2) / (CGFloat(rows) / 2)
                let order = min(1, hypot(gx, gy) / CGFloat(2).squareRoot()) * 0.82 + cellHash(i, j, seed &+ 3) * 0.18
                guard order <= cutoff else { continue }

                // Field value, with the occasional 3-cell block cluster.
                let wi = i + shift
                var sx = CGFloat(wi) * h, sy = CGFloat(j) * h
                if vnoise(sx * 1.3, sy * 1.3, seed &+ 7) > 0.6 {
                    sx = (CGFloat(Int(floor(Double(wi) / 3)) * 3) + 1.5) * h
                    sy = (CGFloat(Int(floor(Double(j) / 3)) * 3) + 1.5) * h
                }
                var v = fbm(sx, sy, seed) - (cover - 0.5) * 0.25

                // Text hole: organic ellipse, inside = deep, near = dissolve through the dither bands.
                var d = CGFloat.infinity
                for hl in holes {
                    let edge = (vnoise(px * 0.2, py * 0.2, seed &+ 9) - 0.5) * 0.32
                    let e = hypot((px - hl.cx) / hl.hx, (py - hl.cy) / hl.hy) + edge
                    d = min(d, (e - 1) * min(hl.hx, hl.hy))
                }
                if d <= 0 { continue }
                v -= 0.9 * max(0, 1 - d / 3)

                guard let color = Tone.color(v, i, j, dark: dark) else { continue }
                ctx.fill(Path(CGRect(x: CGFloat(i) * cell, y: CGFloat(j) * cell, width: cell, height: cell)),
                         with: .color(color), style: FillStyle(antialiased: false))
            }
        }
    }
}

// Text frames reach the field through anchor preferences.
struct ClearKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value += nextValue() }
}
extension View {
    func clearsPixels() -> some View { anchorPreference(key: ClearKey.self, value: .bounds) { [$0] } }
}
```

Rules: the field is never behind text, glass, lists or dense UI. It is decorative (`accessibilityHidden`). Palette stays three colors. Pause it when the window is occluded. Reduce Motion means `reveal = 1`, `drift = 0`, disc in its final state.

---

## 6. Components

All live in `UIComponents`. Features compose them and never build raw controls.

### 6.1 Buttons

Three kinds. Regular height 28, large 32. Capsule, no border, no icon unless the icon carries meaning (`plus` on an add action). Horizontal padding 12 (14 at height 32).

```swift
enum ButtonKind { case primary, secondary, quiet }

struct AppButtonStyle: ButtonStyle {
    var kind: ButtonKind = .secondary
    var height: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, height: height)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let kind: ButtonKind
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        private var fill: Color {
            switch kind {
            case .primary:   configuration.isPressed ? Tok.accentPressed : hover ? Tok.accentHover : Tok.accent
            case .secondary: configuration.isPressed ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control
            case .quiet:     .clear
            }
        }
        private var label: Color {
            switch kind {
            case .primary:   .white
            case .secondary: Tok.text
            case .quiet:     hover || configuration.isPressed ? Tok.text : Tok.text2
            }
        }

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(label)
                .padding(.horizontal, height >= 32 ? 14 : 12)
                .frame(height: height)
                .background(fill, in: .capsule)
                .contentShape(.capsule)
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(Motion.hoverIn, value: configuration.isPressed)
                .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
                .onHover { hover = $0 }
                .clickable(enabled)
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static func app(_ kind: ButtonKind, height: CGFloat = 28) -> AppButtonStyle {
        AppButtonStyle(kind: kind, height: height)
    }
}

/// The one toolbar action per page. System glass, accent tint.
struct ToolbarPrimary: View {
    let title: String
    let glyph: Glyph
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: glyph.rawValue) }
            .buttonStyle(.glassProminent)
            .tint(Tok.accent)
            .clickable()
    }
}
```

At most one accent-filled element per view. The toolbar primary is it.

### 6.2 Card

```swift
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .modifier(ContrastStroke(radius: Radius.card))
    }
}
```

### 6.3 Segmented control (sliding thumb)

Used where a filter is truly needed inside content (History's Raw/Cleaned toggle, Settings pickers with 2 to 4 values). Page-level filters go in the toolbar.

```swift
struct Segmented<T: Hashable>: View {
    struct Item { let value: T; let title: String }
    @Binding var selection: T
    let items: [Item]
    var onCard = false
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                Button { selection = item.value } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == item.value ? Tok.text : Tok.text2)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background {
                            if selection == item.value {
                                Capsule().fill(onCard ? Tok.control : Tok.controlHover)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .clickable()
            }
        }
        .padding(2)
        .background(onCard ? Tok.well : Tok.surface, in: .capsule)
        .animation(reduce ? nil : .smooth(duration: 0.25), value: selection)
    }
}
```

### 6.4 Toggle

```swift
struct AppToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { Track(isOn: configuration.isOn) }
            .buttonStyle(.plain)
            .clickable()
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
    }

    private struct Track: View {
        let isOn: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            Capsule()
                .fill(isOn ? Tok.accent : Tok.controlPressed)
                .frame(width: 34, height: 20)
                .overlay(alignment: .leading) {
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .padding(2)
                        .offset(x: isOn ? 14 : 0)
                }
                .padding(.vertical, 6)                       // 32pt hit target
                .contentShape(.rect)
                .opacity(enabled ? 1 : 0.4)
                .animation(.snappy(duration: 0.2), value: isOn)
        }
    }
}
// Usage: Toggle("Launch at login", isOn: $on).toggleStyle(AppToggleStyle()).labelsHidden()
```

### 6.5 Dropdown (custom trigger, system glass popover)

The popover is system glass. Do not give its content a background.

```swift
struct Dropdown<T: Hashable>: View {
    struct Option: Identifiable { let value: T; let title: String; var id: T { value } }
    @Binding var selection: T
    let options: [Option]
    @State private var open = false
    @State private var cursor: T?
    @State private var hover = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .font(.system(size: 13)).foregroundStyle(Tok.text)
                Icon(glyph: .chevronUpDown, size: 9, weight: .medium).foregroundStyle(Tok.text2)
            }
            .padding(.horizontal, 12).frame(height: 28)
            .background(open ? Tok.controlPressed : hover ? Tok.controlHover : Tok.control, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .clickable()
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(options) { o in
                Button { selection = o.value; open = false } label: {
                    HStack {
                        Text(o.title).font(.system(size: 13)).foregroundStyle(Tok.text)
                        Spacer(minLength: 24)
                        if o.value == selection {
                            Icon(glyph: .checkmark, size: 11, weight: .medium).foregroundStyle(Tok.accentText)
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(cursor == o.value ? Tok.controlHover : .clear,
                                in: .rect(cornerRadius: Radius.field, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .clickable()
                .onHover { inside in cursor = inside ? o.value : (cursor == o.value ? nil : cursor) }
            }
        }
        .padding(6).frame(minWidth: 180)
        .focusable()
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.return) { if let c = cursor { selection = c; open = false }; return .handled }
    }

    private func step(_ d: Int) {
        guard !options.isEmpty else { return }
        let i = options.firstIndex { $0.value == (cursor ?? selection) } ?? 0
        cursor = options[(i + d + options.count) % options.count].value
    }
}
```

Build the same way, with the same tokens: `AppSlider` (4pt capsule track in `well`, accent fill, 14pt white thumb that scales to 1.1 on drag, ms readout in tabular numerals), `AppStepper`, and `KeyRecorder` (shows a keycap, press a key to record, Escape cancels).

### 6.6 Badge (borderless)

Delete `InsetShade`, delete the `.overlay` that draws it, delete the `glow` and `shade` properties. A badge is a tinted fill and colored text. Nothing else.

```swift
struct Badge: View {
    enum Size {
        case lg, md, sm
        var font: CGFloat   { switch self { case .lg: 13; case .md: 12; case .sm: 10 } }
        var px: CGFloat     { self == .lg ? 8 : 6 }
        var height: CGFloat { switch self { case .lg: 24; case .md: 20; case .sm: 18 } }
    }
    @Environment(\.colorScheme) private var scheme
    var text: String
    var variant: BadgeVariant = .neutral
    var size: Size = .md

    var body: some View {
        let dark = scheme == .dark
        Text(text)
            .font(.system(size: size.font))
            .foregroundStyle(variant.text(dark: dark))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, size.px)
            .frame(minHeight: size.height)
            .background(variant.fill(dark: dark), in: .rect(cornerRadius: Radius.field, style: .continuous))
    }
}
```

Badges are for status only: "Denied", "Granted", "Bundled", "Inline", "Common phrase". If a badge is not a status or a label the user acts on, remove it.

### 6.7 KeyCap

Depth is a fill step, not a shadow: the lip is a second surface behind the face. It is how the product teaches its one gesture.

```swift
struct KeyCap: View {
    let label: String
    var down = false
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Tok.text)
            .frame(minWidth: 28, minHeight: 24)
            .padding(.horizontal, 8)
            .background(Tok.controlHover, in: .rect(cornerRadius: Radius.field, style: .continuous))
            .offset(y: down ? 2 : 0)
            .animation(.snappy(duration: 0.12), value: down)
            .background {
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(Tok.control).offset(y: 2)
            }
            .padding(.bottom, 2)
            .accessibilityLabel(label)
    }
}
```

### 6.8 Empty state

One component, two densities. No icon, no pill button. The full stop is the icon.

```swift
struct EmptyState: View {
    enum Density { case page, pane }
    let title: String
    let message: String
    var density: Density = .page

    var body: some View {
        VStack(spacing: density == .page ? 16 : 12) {
            PixelStop(cells: 11, cell: density == .page ? 4 : 3)
            Text(title)
                .font(density == .page ? AppFont.display(28) : .system(size: 15, weight: .medium))
                .tracking(density == .page ? -1.4 : 0)
                .foregroundStyle(Tok.text)
            Text(message)
                .font(.system(size: 13)).foregroundStyle(Tok.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
```

Copy: the title is a sentence that ends (it already has its full stop). The message names the next action and its shortcut, for example "Add one with ⌘N."

### 6.9 Toast (floating glass)

```swift
struct Toast: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                Text(message).font(.system(size: 13)).foregroundStyle(Tok.text)
                if let actionTitle, let action {
                    Button(actionTitle, action: action).buttonStyle(.app(.quiet))
                }
            }
            .padding(.horizontal, 16).frame(height: 40)
            .glassEffect(.regular, in: .capsule)
        }
    }
}
```

### 6.10 Metric and section header

```swift
struct Metric: View {
    let label: String, value: String, note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Tok.text2)
            Text(value).font(.system(size: 28, weight: .medium)).monospacedDigit().foregroundStyle(Tok.text)
                .contentTransition(.numericText())
            Text(note).font(.system(size: 12)).foregroundStyle(Tok.text2)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Tok.text)
            if let note { Text(note).font(.system(size: 12)).foregroundStyle(Tok.text2) }
        }
    }
}
```

### 6.11 Progress without a bar (onboarding)

```swift
struct ProgressDots: View {
    let step: Int, count: Int           // step is 0-based
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Tok.accent : i < step ? Tok.accent.opacity(0.45) : Tok.controlHover)
                    .frame(width: i == step ? 20 : 6, height: 4)
            }
        }
        .animation(reduce ? nil : Motion.settle, value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(count)")
    }
}
```

Downloads show progress as a **row fill**, not a bar:

```swift
struct ProgressRow<Leading: View, Trailing: View>: View {
    let title: String
    let detail: String
    var progress: Double?                       // nil = idle, 0...1 = downloading
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Tok.text)
                Text(detail).font(.system(size: 12)).foregroundStyle(Tok.text2).monospacedDigit()
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 16).frame(height: 64)
        .background(alignment: .leading) {
            GeometryReader { g in
                Rectangle().fill(Tok.accentSoft).frame(width: g.size.width * (progress ?? 0))
                    .animation(Motion.settle, value: progress)
            }
        }
        .background(Tok.surface)
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .modifier(ContrastStroke(radius: Radius.card))
    }
}
```

### 6.12 Contribution graph

53 columns by 7 rows. It sits **directly on the canvas**, no card. Cells are whole device pixels, radius 2, gap 3, five levels from the blue ramp.

```swift
struct ContributionGrid: View {
    let levels: [[Int]]                         // [column][row], 0...4
    static let ramp: [Color] = [
        Color(light: .init(hex: 0xE9E9E9), dark: .init(hex: 0x171717)),
        Color(light: .init(hex: 0xDBEAFE), dark: .init(hex: 0x172554)),
        Color(light: .init(hex: 0x93C5FD), dark: .init(hex: 0x1E3A8A)),
        Color(light: .init(hex: 0x2563EB), dark: .init(hex: 0x2563EB)),
        Color(light: .init(hex: 0x1E3A8A), dark: .init(hex: 0x60A5FA)),
    ]
    @Environment(\.displayScale) private var scale

    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 3
            let cols = CGFloat(max(levels.count, 1))
            let cell = floor(((size.width - gap * (cols - 1)) / cols) * scale) / scale
            let pitch = cell + gap
            for (x, column) in levels.enumerated() {
                for (y, level) in column.enumerated() {
                    let r = CGRect(x: CGFloat(x) * pitch, y: CGFloat(y) * pitch, width: cell, height: cell)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 2, style: .continuous),
                             with: .color(Self.ramp[min(max(level, 0), 4)]))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(7.8, contentMode: .fit)
        .accessibilityLabel("Dictation words per day for the last 12 months")
    }
}
```

Hover tooltip: `onContinuousHover` maps the point to a cell and shows a small floating glass label ("412 words, Oct 14"). The legend ("Less ... More") is five tiny ramp cells with no labels beyond those two words. Reads `daily_stats` only.

---

## 7. Skeleton and pages

### 7.1 Window and sidebar

```
+--------------------------------------------------------------+
| (o)(o)(o)                                    [search] [...] [+ Add] |  <- toolbar: same color as canvas, system glass items
+-----------+--------------------------------------------------+
|           |                                                  |
| glass     |  Page title.                                     |
| sidebar   |  one line of secondary text                      |
|           |                                                  |
| Dashboard |  content on canvas, cards only where grouping    |
| History   |  helps                                           |
| ...       |                                                  |
|           |                                                  |
| ● Ready   |                                                  |
+-----------+--------------------------------------------------+
```

Native `NavigationSplitView` with a sidebar `List(selection:)` and `.listStyle(.sidebar)`. Let Liquid Glass draw selection and the floating sidebar. Do not restyle it, do not draw a custom selected pill. The one custom thing: a **status footer** pinned to the sidebar bottom, showing system state without being asked (DESIGN_RULES §8): a 6pt `Dot` and one word ("Ready", "Warming up", "Basic cleanup", "No microphone access"). Clicking it opens the relevant fix. No hover-only behavior anywhere.

```swift
enum Route: String, CaseIterable, Identifiable, Hashable {
    case dashboard, history, dictionary, shortcuts, meetings, settings
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var glyph: Glyph {
        switch self {
        case .dashboard: .dashboard
        case .history: .history
        case .dictionary: .dictionary
        case .shortcuts: .shortcuts
        case .meetings: .meetings
        case .settings: .settings
        }
    }
}

struct MainWindow: View {
    @State private var route: Route = .dashboard
    var body: some View {
        NavigationSplitView {
            List(Route.allCases, selection: $route) { r in
                Label { Text(r.title) } icon: { Icon(glyph: r.glyph) }.tag(r)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) { EngineStatusFooter() }
        } detail: {
            RouteView(route: route)
                .id(route)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.18), value: route)
        .containerBackground(Tok.bg, for: .window)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(WindowChrome(kind: .main))
        .frame(minWidth: 880, minHeight: 560)
    }
}
```

Keyboard: ⌘1 to ⌘6 switch routes, ⌘F focuses search, ⌘N is the page's add action, ⌘K opens the command palette (system glass floating panel), ⌘⌥S collapses the sidebar. Every action is also a menu-bar command.

### 7.2 Page template

Title in Exposure Italic 28, ending in the pixel full stop, sitting on the baseline like a real period. Subtitle is one line of `text.2` or absent. Nothing else in the header. Search, filters and actions are in the toolbar.

```swift
struct PageTitle: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(title).font(AppFont.display(28)).tracking(-1.4).foregroundStyle(Tok.text)
                PixelStop(cells: 5, cell: 1.5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Tok.text2) }
        }
        .padding(.top, 8)
    }
}

struct Page<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                PageTitle(title: title, subtitle: subtitle)
                content
            }
            .padding(.horizontal, 32).padding(.bottom, 32)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollContentBackground(.hidden)
    }
}
```

Toolbar pattern for every list page (this replaces the header stack):

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Menu {
            Button("Import…") { vm.importEntries() }
            Button("Export…") { vm.exportEntries() }
        } label: { Icon(glyph: .more, size: 16) }
        .accessibilityLabel("More")
    }
    ToolbarItem(placement: .primaryAction) {
        ToolbarPrimary(title: "Add shortcut", glyph: .add) { vm.beginAdd() }
    }
}
.searchable(text: $vm.query, placement: .toolbar, prompt: "Search shortcuts")
```

(Raw `Button` inside a `ToolbarItem` menu is allowed by lint; raw `Button` in page bodies is not.)

### 7.3 Dashboard: one ledger, one graph, one gesture

```
Good evening.●
0 words today. Meetings stay out of these numbers.

+--------------------------------------------------------+
| Words        Time saved     Average speed    Day streak |   one card, four columns,
| 0            0m             --               0 days     |   no icons, no dots
| 0 sessions   estimate       speaking only    0 today    |
+--------------------------------------------------------+

Last 12 months
Dictation words per day
[■■■■■■■■■■■■■■■ 53 x 7 pixel grid, on the canvas ■■■■■■■■■]
Less ▪▪▪▪▪ More

[fn]  Hold, speak, release. Superflow types where your cursor is.
```

- Four tiles become **one ledger card**. Each column is a `Metric`. Gap between columns 48. No icons, no colored dots, no per-column cards.
- The graph has no card and no border. It sits on the canvas.
- When the user has no sessions yet, the bottom row is the `KeyCap("fn")` hint. It presses once on appear (600ms), then rests, and thereafter only moves when the user really holds Fn.
- The old "first dictation" card with the logo in a black box is deleted.
- Refresh icon button is deleted. The view refreshes on appear and on session completion.

```swift
struct DashboardView: View {
    let vm: DashboardViewModel
    var body: some View {
        Page(title: vm.greeting, subtitle: vm.subtitle) {
            Card {
                HStack(alignment: .top, spacing: 48) {
                    Metric(label: "Words", value: vm.words, note: vm.sessionsNote)
                    Metric(label: "Time saved", value: vm.timeSaved, note: "estimate")
                    Metric(label: "Average speed", value: vm.speed, note: "speaking time only")
                    Metric(label: "Day streak", value: vm.streak, note: vm.todayNote)
                }
            }
            .reveal(0)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Last 12 months", note: "Dictation words per day")
                ContributionGrid(levels: vm.levels)
            }
            .reveal(1)
            if vm.isEmpty { HoldToTalkHint().reveal(2) }
        }
    }
}
```

### 7.4 History: a reading room, not a table

```
Today                                |  Slack                    2:14 PM
[icon] Can you send me the budget... |  41 words
       2:14 PM           41 words    |  [ Cleaned | Raw ]
[icon] Notes from the sync with...   |
       1:02 PM           88 words    |  Can you send me the budget before
Yesterday                            |  Thursday? I'd like to look it over...
...                                  |  (selectable, 15pt, measure <= 720)
```

- Two panes. List 320 wide on the canvas, grouped by day with sticky headers in 12pt `text.2`. Rows are 56 tall: the **frontmost app's real icon** (20pt, from `NSWorkspace`) on the left, first line of cleaned text (2 lines max), time on the left of the second line and the word count on the right in tabular numerals. No separators. Hover fills `surface`. Selected fills `control`.
- Detail: header with app name and time, `Segmented` Cleaned / Raw (on the canvas, so `onCard: false`), then the transcript at 15pt, selectable. In Raw mode, words that the cleanup changed are marked with `accentSoft` backgrounds (word-level diff). This is the debugging view the spec asks for; make it feel like a feature.
- Toolbar: search, Copy (`doc.on.doc`), Delete (`trash`) with the undo toast. Delete is also ⌫.
- No filter control. Meetings have their own page and a `Badge("Meeting")` on rows that came from one.
- Empty list: `EmptyState(density: .pane)`. Empty detail: just the `PixelStop` and "Select a session." Nothing else.

### 7.5 Dictionary: sentences, not rows in a table

- Toolbar: search, overflow (Import, Export), primary "Add term" which focuses the composer (⌘N).
- **Composer row** pinned at the top of the list, always visible: `You say [____]  →  You get [____]`. Tab moves, Return adds. If the trigger is a common English word sequence, an orange `Badge("Common phrase")` appears inline with the reason in one line. This replaces the Add sheet.
- The list is grouped into **Terms**, **Corrections** and a collapsed **Bundled** group. The All / Terms / Corrections filter control is deleted because the groups already say it.
- Row (36pt): trigger in `text.2`, `arrow` glyph, result in `text` Medium. Clicking a row expands it in place for editing. Delete via ⌫ and the context menu. Disabled entries are `text.2` with the toggle shown.
- **Playground** at the bottom, one card: "Try it". A text field; the output below shows the live Tier 0 result, with changed spans in `accentSoft`. It runs the deterministic Tier 0 `TextPipeline` only (under 5ms), so it can run on every keystroke.

```swift
struct EntryRow: View {
    let trigger: String
    let result: String
    var badge: (text: String, variant: BadgeVariant)?
    var isDisabled = false
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 16) {
                Text(trigger).font(.system(size: 13)).foregroundStyle(Tok.text2)
                    .frame(width: 200, alignment: .leading).lineLimit(1)
                Icon(glyph: .arrow, size: 11).foregroundStyle(Tok.text2)
                Text(result).font(.system(size: 13, weight: .medium)).foregroundStyle(isDisabled ? Tok.text2 : Tok.text).lineLimit(1)
                Spacer(minLength: 16)
                if let badge { Badge(text: badge.text, variant: badge.variant) }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(hover ? Tok.surface : .clear, in: .rect(cornerRadius: Radius.nested, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .clickable()
    }
}
```

### 7.6 Shortcuts

Same skeleton as Dictionary so the app feels like one system, with these differences: the composer is `Say [trigger]` then a multi-line monospaced editor (SF Mono 12) that grows to 6 lines; rows show the trigger and the first line of the expansion in mono, truncated; the `Badge("Inline")` appears only on inline-match shortcuts (whole utterance is the implied default, so the All / Whole utterance / Inline filter is deleted). The 200 KB limit shows as a tabular counter only above 80% of the limit, never as a permanent footnote.

### 7.7 Meetings

- List rows (64pt): title and date on the left, duration right in tabular numerals, and under the title a **speaker barcode**: 96 cells, 3pt wide, one per time slice, colored by who spoke (You = `accent`, remote speakers = `text.2` at 100%, 60%, 35% opacity, silence = `controlHover`). It is the pixel language of the brand and shows the shape of a meeting at a glance.
- Detail: turns in a two-column layout. A sticky left column (120pt) holds the speaker name and timestamp, the right column holds the text (15pt, measure at most 720). Speaker names are renameable inline.
- Toolbar: Copy as Markdown (primary, since that is the main use), overflow with Export Markdown and Export JSON.
- Empty state: "Meetings start with a hold." The message names the gesture and shows `KeyCap("⌘")` with the word "right" next to it. No button.

### 7.8 Settings: custom controls, no form wall

- Sections (General, Dictation, Text, Meetings, Privacy, Advanced), each a `Card` with 8pt padding and rows of at least 48pt. Section title above each card in `SectionHeader`. Search lives in the toolbar and filters rows by title and help text.
- Rows: title 13 Medium, help 12 `text.2` on the left, control on the right. **No row hover fill** (a hover fill promises a click that is not there). No dividers: row spacing only.
- Controls are the custom ones from section 6: `AppToggleStyle`, `Dropdown` (speech model, number style, line breaks, retention), `AppSlider` (gesture timings in ms, with a tabular readout), `AppStepper` (typing speed, line-break word counts), `KeyRecorder` (hotkeys), `Segmented(onCard: true)` for two to four values.
- No native `Picker`, `Toggle` or `Slider` appearance anywhere. If you reach for one, build the custom version.

```swift
struct SettingRow<Control: View>: View {
    let title: String
    var help: String?
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Tok.text)
                if let help { Text(help).font(.system(size: 12)).foregroundStyle(Tok.text2) }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 12).frame(minHeight: 48)
    }
}
```

---

## 8. Onboarding: four steps, one backdrop

Window: 640 x 520, fixed, no zoom, transparent titlebar, canvas to the top edge, traffic lights floating. Content column 480 wide. No window title text. No "Step x of 8" label.

### 8.1 Structure

| # | Title (Exposure Italic 40) | Content | Primary |
|---|---|---|---|
| 1 | Speak. It types. | One line of body. A `KeyCap("fn")` that presses and releases once. The privacy line, stated once. | Continue |
| 2 | Four permissions. | Four rows: Microphone, Accessibility, Input Monitoring, and the Globe key (detected, with "Open Keyboard settings" when it needs to be Do Nothing). Each row: title, one-line reason, trailing control: neutral `Grant` or `Open Settings` as a secondary button at 24, or `Granted` with a `checkmark`. Continue is the only accent-filled element on the screen. Rows re-check on `didBecomeActive`. No Recheck button, no "0 of 3" counter. | Continue (enabled when the three required are granted, `Set up later` otherwise) |
| 3 | Download the models. | Two `ProgressRow`s: the speech model (required) and the cleanup model (optional, with a toggle). One primary "Download" starts both. Progress is the row fill and a tabular "42 MB of 130 MB" line. | Continue |
| 4 | You're set.● | One sentence. A sandbox text field (placeholder "Hold fn and say something") only when microphone and speech model are ready. The pixel disc lands after the title as the full stop. | Open Superflow |

Cut: the Meetings step (system audio is requested lazily on the first meeting, as the build plan already says), the summary list, and the display-name field (it lives in Settings, default empty; the greeting adapts).

### 8.2 Shell

Primary at height 32, large padding 14. Back and "Set up later" are quiet text buttons. The progress dots sit centered in the footer. Footer height 64. The text blocks mark themselves with `.clearsPixels()` so the field opens its organic hole around them.

```swift
struct OnboardingShell<Content: View>: View {
    let step: Int, count: Int
    let primaryTitle: String
    var primaryEnabled = true
    var reveal: CGFloat = 1                 // owned by OnboardingView, animated once at launch
    var backAction: (() -> Void)?
    var skipTitle: String?
    var skipAction: (() -> Void)?
    let primaryAction: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: 480, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 72)
                .clearsPixels()
            footer
        }
        .frame(width: 640, height: 520)
        .background(Tok.bg)
        .backgroundPreferenceValue(ClearKey.self) { anchors in
            GeometryReader { geo in
                PixelField(clear: anchors.map { geo[$0] }, cover: 0.42, reveal: reveal)
            }
        }
        .containerBackground(Tok.bg, for: .window)
        .background(WindowChrome(kind: .onboarding))
    }

    private var footer: some View {
        ZStack {
            ProgressDots(step: step, count: count)
            HStack(spacing: 8) {
                if let backAction { Button("Back", action: backAction).buttonStyle(.app(.quiet)) }
                Spacer()
                if let skipTitle, let skipAction { Button(skipTitle, action: skipAction).buttonStyle(.app(.quiet)) }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.app(.primary, height: 32))
                    .disabled(!primaryEnabled)
            }
        }
        .padding(.horizontal, 24).frame(height: 64)
        .clearsPixels()
    }
}
```

Drive the reveal once, in whole steps, from `OnboardingView`:

```swift
@State private var reveal: CGFloat = 0
@Environment(\.accessibilityReduceMotion) private var reduce

.task {
    guard !reduce else { reveal = 1; return }
    let n = 14
    for k in 1...n {
        try? await Task.sleep(for: .milliseconds(1300 / n))
        reveal = CGFloat(k) / CGFloat(n)
    }
}
```

### 8.3 Progress drives the field

The step index is the single progress value, `p = step / (count - 1)`, eased per section 5.2. Steps 1 to 3: the field is alive around the text hole. Step 4: run `DESIGN.md` §8.6 (ring collapse) then §8.7 (disc grows, then travels along an arc to the slot measured live at the end of the title). Never from timers. Never a second animation on top. Tune `cover` and the clear padding until the field reads as a frame at the corners and a band above the title, and never competes with the text.

### 8.4 Vendor marks

The Parakeet row shows the **NVIDIA mark** at 20pt, rendered as a template image in `text`, monochrome. This is a vendor mark, not a UI icon, so the SF Symbols rule does not apply to it. Use NVIDIA's own official asset and read their logo usage guidelines first; I could not confirm what a third-party app is permitted to do. If the guidelines do not allow it, set the word "NVIDIA" in SF Pro Medium 12 as a plain text reference instead. The cleanup row uses the `cleanup` glyph (`textformat`), not a sparkle: sparkles are the generic AI mark.

Model description lines are plain sentences, not dotted chains: "Streaming speech recognition for English. Runs on this Mac." and "Removes filler words and fixes punctuation. Optional."

---

## 9. Enforcement (extend `tools/lint-forbidden`)

By construction, not by good intentions. Fail the build on:

- `.stroke(`, `.strokeBorder(`, `.border(`, `.overlay(` containing a stroke, outside `ContrastStroke` and `focusRing`
- `Image(systemName:` outside `Icon` and `Label(..., systemImage:)` inside `ToolbarPrimary`; any import of Hugeicons or Phosphor assets
- `Color(hex:` or any hex literal outside `DesignSystem`
- raw `Button`, `Toggle`, `Picker`, `Slider`, `Stepper`, `onTapGesture`, `NSCursor` in Feature packages (toolbar menus excepted)
- `.pointerStyle` outside the `clickable()` modifier
- weights heavier than `.medium`
- fixed font sizes outside the type table
- any `.animation(.linear`, `.easeInOut`, `.spring(`, `.bouncy`
- files over 400 lines, as before

Add a `DEBUG` launch check that runs `validateGlyphs()` and `validateDisplayFont()`.

---

## 10. Acceptance checklist

Run it per route, in dark and light, at 2x, in the screenshots you attach.

- [ ] Titlebar and toolbar are the exact canvas color. Traffic lights float on it. No "Superflow" title text.
- [ ] Zero strokes anywhere (outside focus ring and Increase Contrast). Zero hairline dividers.
- [ ] Surfaces separate by background step alone, and the steps are visible on a real display in both modes.
- [ ] Every icon is an SF Symbol and is bare. No icon in a box, circle or badge. No icon that carries no meaning.
- [ ] No progress bar. Onboarding is 4 steps with the dots and the row-fill progress.
- [ ] Each page has its own skeleton (7.3 to 7.8). Search and filters are in the toolbar. One primary action per page, in the toolbar. No duplicated button in the empty state.
- [ ] Every page title ends in the pixel full stop. Every empty state is built on it.
- [ ] Only blue 600 as accent. One accent-filled element per view.
- [ ] Badges are borderless and used for status only.
- [ ] Regular and Medium only. Exposure Italic loads (the debug check passes) and appears only at 28 and 40. All changing numbers are tabular.
- [ ] Spacing from the 4pt scale. Page padding 32, card padding 20, control heights 24 / 28 / 32. Window 960 x 620 default, 880 x 560 min; onboarding 640 x 520 fixed.
- [ ] Pointer hand on everything clickable, arrow on disabled, I-beam on text. Verified by hovering each control.
- [ ] Custom Dropdown, Toggle, Slider, Stepper, Segmented and KeyRecorder in Settings, all with focus rings, VoiceOver labels and keyboard operation.
- [ ] Glass only on sidebar, toolbar, popovers, toasts, palette, Island. No glass on glass, no hand-made blur.
- [ ] Motion: nothing bounces or loops, route change is an opacity fade, selection and segmented thumbs slide, numbers roll, graph reveals once in whole steps.
- [ ] Reduce Motion renders final states. Reduce Transparency falls back to solid `surface`. Increase Contrast shows the 1pt stroke.
- [ ] Copy: sentence case, verb-led, no middle-dot chains, no trailing arrows, the privacy line stated once in onboarding and once in Settings.
- [ ] `make verify` is green, lint rules from section 9 are in, `DESIGN.md` is rewritten to match.
- [ ] Swap-the-logo test passes on every screen.

The pixel-bar scrubber I gave you in the directive was the obvious version, so I threw it out. The new one is a pixel **spectrogram**: eight frequency rows by time columns, built from the real audio. It uses the same cell language as your 12-month graph.

- **What you can see in it:** words show up as shapes. "s" and "sh" light the top rows, vowels light the middle, hum sits on the bottom row. If a clip is noisy, you see it before you press play.
- **Scrub to hear:** drag across the picture and you hear a 90 ms grain at the pointer, like a tape head. That is how you find the exact spot where "I worn next" went wrong.
- **Playback:** unplayed cells are dim neutral. The scan column passes and they ignite to blue, with a short dithered cooling trail (checker steps, no gradient). The clip also "develops" in 14 whole steps when it loads.
- **States:** loading, ready, playing, paused, ended and unavailable are all drawn. The grid never changes size between them.

Single file, drop-in: `AudioPreview(url: AudioStore.url(for: session.id))`.

```swift
//  AudioPreview.swift
//
//  A picture of your voice you can drag across to hear it.
//
//  The clip is decoded once, turned into an 8-band pixel spectrogram (rows = frequency, columns = time),
//  and cached. Dragging plays short Hann-windowed grains under the pointer (tape-head scrub). Playing
//  lights the cells blue behind a scan column with a dithered cooling trail.
//
//  Depends on (adjust names to the real ones): Tok, Radius, Motion, Icon(_:size:tint:) with new Glyph cases
//  `.play` ("play.fill") and `.pause` ("pause.fill"), ContributionGrid.ramp (make it public if needed),
//  `.contrastStroke(radius:)`, `.clickable()`. Nothing else.
//
//  Usage:  AudioPreview(url: AudioStore.url(for: session.id))

import Accelerate
import AVFoundation
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

// Swap for AppType.caption / .label once the pass 3 type tokens land.
private enum T {
    static let caption = Font.system(size: 12)
    static let label = Font.system(size: 13, weight: .medium)
}

// MARK: - Spectrogram

private enum Spectro {
    static let bands = 8
    static let window = 512                                       // 32 ms at 16 kHz
    static let hop = 400                                          // 25 ms
    static let edges = [0, 8, 16, 32, 48, 74, 109, 160, 256]      // FFT bins, 31.25 Hz each
    /// dB added per band so speech's natural low-frequency tilt does not swallow the consonants.
    static let tilt: [Float] = [0, 2, 4, 6, 8, 10, 12, 14]
    static let range: Float = 38                                  // dB shown below the loudest cell
    static let gateDB: Float = -62                                // frames quieter than this are silence
}

struct ClipData: Sendable {
    let url: URL
    let samples: [Float]            // mono, kept so playback and grains never touch the disk
    let sampleRate: Double
    let duration: TimeInterval
    let frames: Int
    let cells: [UInt8]              // frames x 8, row-major by frame, 0...255
}

enum ClipLoader {
    private final class Box { let clip: ClipData; init(_ clip: ClipData) { self.clip = clip } }
    private static let cache: NSCache<NSURL, Box> = {
        let c = NSCache<NSURL, Box>(); c.totalCostLimit = 96_000_000; return c
    }()

    static func load(_ url: URL) async -> ClipData? {
        if let hit = cache.object(forKey: url as NSURL) { return hit.clip }
        let clip = await Task.detached(priority: .userInitiated) { ClipLoader.decode(url) }.value
        if let clip { cache.setObject(Box(clip), forKey: url as NSURL, cost: clip.samples.count * 4) }
        return clip
    }

    nonisolated private static func decode(_ url: URL) -> ClipData? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let cells = analyze(samples)
        guard !cells.isEmpty else { return nil }
        let rate = file.processingFormat.sampleRate
        return ClipData(url: url, samples: samples, sampleRate: rate,
                        duration: Double(samples.count) / rate,
                        frames: cells.count / Spectro.bands, cells: cells)
    }
}

private func analyze(_ samples: [Float]) -> [UInt8] {
    let n = Spectro.window, half = n / 2, bands = Spectro.bands
    guard samples.count >= n else { return [] }
    let frames = (samples.count - n) / Spectro.hop + 1
    let log2n = vDSP_Length(log2(Double(n)))
    guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
    defer { vDSP_destroy_fftsetup(setup) }

    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

    var windowed = [Float](repeating: 0, count: n)
    var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
    var power = [Float](repeating: 0, count: half)
    var db = [Float](repeating: -200, count: frames * bands)
    var maxDB: Float = -200

    for f in 0..<frames {
        var rms: Float = 0
        samples.withUnsafeBufferPointer { p in
            vDSP_rmsqv(p.baseAddress! + f * Spectro.hop, 1, &rms, vDSP_Length(n))
            vDSP_vmul(p.baseAddress! + f * Spectro.hop, 1, window, 1, &windowed, 1, vDSP_Length(n))
        }
        guard 20 * log10(max(rms, 1e-7)) > Spectro.gateDB else { continue }       // silence stays at -200

        windowed.withUnsafeBufferPointer { w in
            w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { c in
                re.withUnsafeMutableBufferPointer { r in
                    im.withUnsafeMutableBufferPointer { i in
                        var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                        vDSP_ctoz(c, 2, &split, 1, vDSP_Length(half))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
                    }
                }
            }
        }
        power[0] = 0                                   // bin 0 packs DC and Nyquist together; drop it
        for b in 0..<bands {
            let lo = Spectro.edges[b], hi = Spectro.edges[b + 1]
            var mean: Float = 0
            power.withUnsafeBufferPointer { vDSP_meanv($0.baseAddress! + lo, 1, &mean, vDSP_Length(hi - lo)) }
            let v = 10 * log10(max(mean, 1e-12)) + Spectro.tilt[b]
            db[f * bands + b] = v
            maxDB = max(maxDB, v)
        }
    }
    guard maxDB > -150 else { return [UInt8](repeating: 0, count: db.count) }     // all silence
    let low = maxDB - Spectro.range
    return db.map { $0 <= low ? 0 : UInt8(min(255, (($0 - low) / Spectro.range * 255).rounded())) }
}

// MARK: - Player (AVAudioEngine over the decoded samples)

@MainActor @Observable
final class ClipPlayer {
    enum State { case idle, playing, paused }
    private(set) var state: State = .idle
    private(set) var duration: TimeInterval = 0
    private(set) var moves = 0                        // bumps on seek and scrub so a paused view redraws

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private var clip: ClipData?
    @ObservationIgnored private var format: AVAudioFormat?
    @ObservationIgnored private var grainWindow: [Float] = []
    @ObservationIgnored private var startSample = 0          // sample where the running segment began
    @ObservationIgnored private var parked: TimeInterval = 0
    @ObservationIgnored private var generation = 0           // invalidates stale completion callbacks
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var lastGrain: TimeInterval = -1

    /// Position in seconds. Read once per frame by the views. Deliberately not observed.
    var time: TimeInterval {
        guard state == .playing, let clip, let nodeTime = node.lastRenderTime,
              let p = node.playerTime(forNodeTime: nodeTime) else { return parked }
        return min(clip.duration, Double(startSample) / clip.sampleRate + Double(p.sampleTime) / p.sampleRate)
    }

    func load(_ clip: ClipData) {
        stop()
        self.clip = clip
        duration = clip.duration
        parked = 0
        let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: clip.sampleRate, channels: 1, interleaved: false)!
        format = f
        if node.engine == nil { engine.attach(node) }
        engine.connect(node, to: engine.mainMixerNode, format: f)
        engine.prepare()
        let n = Int(clip.sampleRate * 0.09)                      // 90 ms grains
        grainWindow = [Float](repeating: 0, count: n)
        vDSP_hann_window(&grainWindow, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
    }

    func play() {
        guard let clip else { return }
        start(at: parked >= clip.duration - 0.02 ? 0 : parked)
    }
    func pause() {
        guard state == .playing else { return }
        parked = time; generation += 1; node.stop(); state = .paused; moves += 1
    }
    func toggle() { if state == .playing { pause() } else { play() } }
    func seek(_ t: TimeInterval) {
        let t = min(max(t, 0), duration)
        if state == .playing { start(at: t) } else { parked = t; moves += 1 }
    }
    func stop() {
        generation += 1; node.stop(); engine.stop()
        state = .idle; parked = 0; scrubbing = false
    }

    // MARK: tape-head scrub

    func beginScrub() {
        resumeAfterScrub = state == .playing
        if state == .playing { parked = time; generation += 1; node.stop(); state = .paused }
        scrubbing = true; lastGrain = -1
        guard ensureRunning() else { return }
        node.play()                                              // runs silent until a grain arrives
    }
    func scrub(to t: TimeInterval) {
        guard scrubbing, let clip, let format else { return }
        let t = min(max(t, 0), clip.duration)
        parked = t; moves += 1
        guard abs(t - lastGrain) > 0.012 else { return }         // 12 ms: more events than that adds nothing audible
        lastGrain = t
        let at = Int(t * clip.sampleRate), end = min(at + grainWindow.count, clip.samples.count)
        guard end - at > 64, let buf = buffer(at..<end, format) else { return }
        let p = buf.floatChannelData![0]
        vDSP_vmul(p, 1, grainWindow, 1, p, 1, vDSP_Length(end - at))             // Hann: no clicks
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }
    func endScrub() {
        guard scrubbing else { return }
        scrubbing = false
        node.stop()
        if resumeAfterScrub { start(at: parked) }
    }

    // MARK: internals

    private func start(at t: TimeInterval) {
        guard let clip, let format, ensureRunning() else { return }
        let from = min(max(Int(t * clip.sampleRate), 0), clip.samples.count - 1)
        guard let buf = buffer(from..<clip.samples.count, format) else { return }
        generation += 1
        let gen = generation
        node.stop()
        startSample = from
        node.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == gen, self.state == .playing else { return }
                self.parked = clip.duration; self.state = .paused; self.moves += 1
            }
        }
        node.play()
        state = .playing
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        return (try? engine.start()) != nil
    }

    private func buffer(_ range: Range<Int>, _ format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let clip, let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)) else { return nil }
        b.frameLength = AVAudioFrameCount(range.count)
        clip.samples.withUnsafeBufferPointer {
            b.floatChannelData![0].update(from: $0.baseAddress! + range.lowerBound, count: range.count)
        }
        return b
    }
}

// MARK: - The picture

struct SpectroScrubber: View {
    let clip: ClipData?                       // nil while loading or when unavailable: the grid sits dormant
    let unavailable: Bool
    let player: ClipPlayer
    @Binding var hover: TimeInterval?
    var onTouch: () -> Void = {}

    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var scrubbing = false
    @State private var reveal: CGFloat = 0

    private let rows = Spectro.bands
    private let gap: CGFloat = 2

    /// Square cells, about 4pt, solved so the last column ends on the content edge, snapped to device pixels.
    private func layout(_ w: CGFloat) -> (cols: Int, cell: CGFloat) {
        let cols = max(1, Int((w + gap) / (4 + gap)))
        return (cols, floor(((w - gap * CGFloat(cols - 1)) / CGFloat(cols)) * scale) / scale)
    }
    private var gridHeight: CGFloat {
        let cell = width > 0 ? layout(width).cell : 4
        return CGFloat(rows) * cell + CGFloat(rows - 1) * gap
    }

    var body: some View {
        let _ = player.moves                                       // dependency: redraw after seek/scrub while paused
        TimelineView(.animation(paused: player.state != .playing && !scrubbing)) { _ in
            Canvas { ctx, size in draw(&ctx, size, played: player.time) }
        }
        .frame(height: gridHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay {
            if unavailable { Text("Audio unavailable").font(T.caption).foregroundStyle(Tok.text2) }
        }
        .contentShape(.rect)
        .gesture(scrub)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): hover = clip == nil ? nil : time(at: p.x)
            case .ended: hover = nil
            }
        }
        .task(id: clip?.url) { await develop() }
        .clickable(clip != nil)
        .accessibilityElement()
        .accessibilityLabel("Recording")
        .accessibilityValue(clock(player.time))
        .accessibilityAdjustableAction { d in player.seek(player.time + (d == .increment ? 1 : -1)) }
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard clip != nil else { return }
                if !scrubbing { scrubbing = true; onTouch(); player.beginScrub() }
                player.scrub(to: time(at: g.location.x))
            }
            .onEnded { _ in
                guard scrubbing else { return }
                scrubbing = false
                player.endScrub()
            }
    }

    private func time(at x: CGFloat) -> TimeInterval {
        guard width > 0, let clip else { return 0 }
        return min(max(x / width, 0), 1) * clip.duration
    }

    /// The clip "develops" in 14 whole steps, once, like the 12-month graph. Reduce Motion skips it.
    private func develop() async {
        guard clip != nil else { reveal = 0; return }
        guard !reduceMotion else { reveal = 1; return }
        reveal = 0
        for step in 1...14 {
            try? await Task.sleep(for: .milliseconds(34))
            if Task.isCancelled { return }
            reveal = CGFloat(step) / 14
        }
    }

    // MARK: drawing

    private func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

    private func level(_ d: ClipData, col c: Int, of cols: Int, band b: Int) -> Int {
        let n = d.frames
        var v: UInt8 = 0
        if n >= cols {                                              // more frames than columns: max-pool
            let lo = c * n / cols
            for f in lo..<min(max(lo + 1, (c + 1) * n / cols), n) { v = max(v, d.cells[f * Spectro.bands + b]) }
        } else {                                                    // short clip: nearest frame, pixels stay honest
            v = d.cells[min(n - 1, c * n / cols) * Spectro.bands + b]
        }
        return v < 40 ? 0 : v < 110 ? 1 : v < 180 ? 2 : 3
    }

    /// Deterministic 0...1 per cell, for the stepped reveal.
    private func jitter(_ i: Int, _ j: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: i) &* 374761393 &+ UInt32(truncatingIfNeeded: j) &* 668265263 &+ 7 &* 2246822519
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Double(h) / Double(UInt32.max)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, played: TimeInterval) {
        let (cols, cell) = layout(size.width)
        let pitch = cell + gap
        let ramp = ContributionGrid.ramp
        let ahead = [Tok.control, Tok.controlHover, Tok.controlPressed]       // unplayed: quiet neutral steps
        let settled = [ramp[1], ramp[2], Tok.accent]                          // played: navy to blue 600
        let progress = clip.map { $0.duration > 0 ? played / $0.duration : 0 } ?? 0
        let head = min(max(Int(progress * Double(cols)), 0), cols - 1)
        let ghost = hover.flatMap { h in clip.map { min(max(Int(h / $0.duration * Double(cols)), 0), cols - 1) } }
        let eased = 1 - pow(1 - Double(reveal), 3)
        let cutoff = (eased * 14).rounded(.up) / 14

        for c in 0..<cols {
            let k = head - c                                                  // columns behind the head; < 0 = ahead
            for b in 0..<rows {
                let lv = clip.map { level($0, col: c, of: cols, band: b) } ?? 0
                let order = Double(c) / Double(cols) * 0.82 + jitter(c, b) * 0.18
                let lit = lv > 0 && order <= cutoff
                let checker = (c + b) % 2 == 0

                var tone = Tok.well
                if lit {
                    switch k {
                    case ..<0: tone = ahead[lv - 1]
                    case 0:    tone = Tok.text
                    case 1:    tone = checker ? Tok.text : ramp[4]             // cooling trail, dithered, no gradient
                    case 2:    tone = ramp[4]
                    case 3:    tone = checker ? ramp[4] : settled[lv - 1]
                    default:   tone = settled[lv - 1]
                    }
                } else if k == 0 && clip != nil && cutoff >= 1 {
                    tone = Tok.controlPressed                                  // the scan guide crosses silence too
                }
                if c == ghost && k != 0 { tone = lit ? Tok.text2 : Tok.control }   // where a click would land

                let rect = CGRect(x: snap(CGFloat(c) * pitch), y: snap(CGFloat(rows - 1 - b) * pitch),
                                  width: cell, height: cell)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1, style: .continuous), with: .color(tone))
            }
        }
    }
}

// MARK: - Card

struct AudioPreview: View {
    let url: URL
    @State private var player = ClipPlayer()
    @State private var clip: ClipData?
    @State private var failed = false
    @State private var hover: TimeInterval?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SpectroScrubber(clip: clip, unavailable: failed, player: player, hover: $hover,
                            onTouch: { focused = true })
            HStack(spacing: 8) {
                PlayButton(playing: player.state == .playing, enabled: clip != nil) {
                    focused = true
                    player.toggle()
                }
                Readout(player: player, hover: hover, total: clip?.duration ?? 0)
                Spacer(minLength: 16)
                // Discoverability for the one non-obvious gesture. Fades in with the pointer.
                Text("Drag to hear")
                    .font(T.caption).foregroundStyle(Tok.text2)
                    .opacity(hover != nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: hover != nil)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .contrastStroke(radius: Radius.card)
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { player.toggle(); return .handled }
        .onKeyPress(.leftArrow) { player.seek(player.time - 1); return .handled }
        .onKeyPress(.rightArrow) { player.seek(player.time + 1); return .handled }
        .task(id: url) { await load() }
        .onDisappear { player.stop() }
    }

    private func load() async {
        player.stop(); clip = nil; failed = false
        guard let loaded = await ClipLoader.load(url) else { failed = true; return }
        guard !Task.isCancelled else { return }
        player.load(loaded)
        clip = loaded
    }
}

private struct PlayButton: View {
    let playing: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Icon(playing ? .pause : .play, size: 16, tint: Tok.text)
                .contentTransition(.symbolEffect(.replace))         // Apple's own morph between the two glyphs
                .frame(width: 32, height: 32)
                .background(hover && enabled ? Tok.control : .clear, in: .circle)   // bare at rest, fill on hover
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hover = $0 }
        .animation(hover ? Motion.hoverIn : Motion.hoverOut, value: hover)
        .animation(.snappy(duration: 0.2), value: playing)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .clickable(enabled)
        .accessibilityLabel(playing ? "Pause" : "Play")
    }
}

/// Current time in `text`, total in `text2`, tenths of a second. While the pointer is over the picture it
/// shows the time under the pointer: the readout is the tooltip.
private struct Readout: View {
    let player: ClipPlayer
    let hover: TimeInterval?
    let total: TimeInterval

    var body: some View {
        let _ = player.moves
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: player.state != .playing)) { _ in
            HStack(spacing: 8) {
                Text(clock(hover ?? player.time)).foregroundStyle(Tok.text)
                Text(clock(total)).foregroundStyle(Tok.text2)
            }
            .font(T.label).monospacedDigit()
        }
    }
}

private func clock(_ t: TimeInterval) -> String {
    let tenths = max(0, Int((t * 10).rounded(.down)))                // floor, so 59.96 never prints 0:60.0
    return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}
```

**Wiring and what changed from the directive**

- This replaces `AudioPlayerModel`, `PixelScrubber` and `AudioPreview` from sections 6.4 to 6.6. Keep the writer in 6.1 and the tee in 6.2.
- **No peaks and no schema columns needed.** The spectrogram is computed on load from the file and cached, so drop `audio_peaks` and `audio_duration`. "Is there audio" is just `FileManager.fileExists`. The writer can stop computing peaks.
- I cut the 1x / 1.5x / 2x button. Dictation clips are seconds long, and a time-pitch node would break the sample-clock position math.

**What I could not verify (not compiled)**

- **vDSP FFT block:** check the band picture on a real clip. Say "sign off" and look for the "s" in the top rows. If it looks like mush, tune `tilt`, `range` and the three level thresholds (40, 110, 180).
- **Playback position:** it is `startSample + playerTime.sampleTime`. Check it stays glued to the sound.
- **Grain clicks:** the Hann window should kill them. Listen for any left.
- **Engine route changes:** the engine does not handle output-device changes yet.
- **API names:** `Icon(_:size:tint:)`, `.clickable()`, `.contrastStroke` and `ContributionGrid.ramp` access are matched to what I saw in your code. Fix any that differ.
- **Contrast:** the unplayed neutral steps (1F, 26, 2E on 17) are meant to be quiet. If the picture is invisible on your display, raise the steps. Do not add strokes.