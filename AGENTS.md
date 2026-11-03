# Superflow agent guide

TOKEN BUDGET RULES. Follow strictly. Quality must not drop, waste must.

Spend tokens ONLY on: (1) understanding the code, (2) writing correct edits, (3) sharp testing. Everything else is waste.

NEVER
- Never spawn sub-agents, background agents, or delegated/parallel tasks. Work alone, in this session.
- Never re-read a file you already read this session unless it changed.
- Never narrate, recap, or restate the plan, the task, or my message.
- Never dump large outputs (logs, full test output, big diffs, whole files) into context. Cap with head/tail/grep.
- Never rewrite whole files, reformat, rename, or refactor anything unrelated to the task.
- Never guess. If a requirement is ambiguous, ask ONE short question first.

1. CONTEXT (spend heavily here)
- Locate relevant files with grep/glob first. Do not read the whole repo.
- Read every relevant file IN FULL in one pass (not many small slices that cause repeated reads): the files to change, their direct callers/callees, related types/config, and the existing tests for that area.
- Find the root cause or exact insertion point BEFORE touching anything. Name it in one sentence.

2. PLAN
- If the task touches 3+ files or the cause is unclear: write plan.md (root cause, files to change, exact changes, how each will be verified). Keep it under 40 lines. Then execute it without asking me.
- If the task is small, skip plan.md and state the fix in one line.

3. EDIT (spend heavily here)
- Make minimal, surgical patches. Change only what the plan requires.
- Match existing style and conventions. Handle edge cases the plan named.
- Re-read your own patch once for correctness before testing.

4. TEST (sharp, not broad)
- First, reproduce the bug or define the one check that proves the feature works. Run it BEFORE the fix if it is a bug.
- Run only tests that cover the changed code: single test or single file, fail-fast, quiet mode. Never run the full suite repeatedly.
- Limit output (e.g. tail -n 30, grep for failures). Read only what failed.
- If a test fails: read the failure, re-read the relevant code, then fix. Do NOT re-run the same command hoping for a different result. Same failure twice means stop and rethink, not retry.
- After the fix passes, run the nearest related tests once. Run the full suite ONLY once at the very end, and only if it is fast. Skip lint/build/format unless they cover what you changed.
- Never claim success without a passing run you actually saw.

5. FINISH
- Final reply: max 5 lines. What was wrong, what changed (files), what was verified, anything not verified. Delete plan.md only if I ask.

Ship the requested behavior completely. Preserve correctness, privacy, accessibility, architecture, and visual quality. Save usage through focused context and verification, never by weakening acceptance criteria.

## Issue tracking

- At the start of every task, read [issue.md](issue.md) and check its status before acting on a recorded issue.
- Record confirmed significant medium or larger bugs, fundamental feature failures, and catastrophic issues. Ignore minor bugs; use judgment for medium issues.
- Add each issue under `# Issue` with a short title, a description under 20 words, and exactly one checked status: `Unresolved` or `Resolved`. Include concise evidence or verification when useful.
- After fixing an issue, verify the fix and mark it `Resolved` in issue.md. If it remains unfixed or unverified, leave it `Unresolved`.
- When resolving an issue, update the latest resolution below with its title and verification.

Latest resolution: None recorded.

<!-- INIT-RULES:START — do not remove this marker. Managed by `init rules`. -->
Read [GIT-SKILLS.md](GIT-SKILLS.md) before Git writes. Read [RULES.md](RULES.md) for substantial engineering work. Small, low-risk edits use inspect → edit → verify.

This guide overrides blanket full-repository reading and repeated-check mandates in referenced documents. Load task-relevant context; preserve required release gates. Git conflicts resolve in favor of GIT-SKILLS.md: stage explicit paths; do not pull or stage everything.
<!-- INIT-RULES:END -->

## Product and architecture

Superflow is a native, local macOS 15+ dictation and meeting app for Apple silicon. Swift 6 strict concurrency, SwiftUI, AppKit host integration, SQLite WAL. No shipped web frontend, Python, cloud inference, accounts, or telemetry. Network use is limited to model downloads and optional update checks. Never log transcript text or audio.

| Location | Ownership and allowed dependencies |
| --- | --- |
| `Packages/L0-Core` | Kernel types, Ports protocols, TestKit fakes; core dependencies only |
| `Packages/L1-Adapters` | Audio, ASR, LLM, storage, insertion, permissions; depend on L0 |
| `Packages/L2-Engines` | Session, meeting, recovery, gestures, text stages; depend on L0 and L2 |
| `Packages/L3-Features` | Views and view models; depend on L0, L2, and L4 |
| `Packages/L4-UI` | DesignSystem, Icons, UIComponents; depend on L0 and L4 |
| `App/SuperflowApp` | Composition root and coordinator; wires concrete adapters into engines |
| `App/InferenceHelper` | XPC service owning llama.cpp inference; ASR currently remains in the app |

Flow: gesture → audio capture and durable journal → streaming ASR → deterministic text stages → local cleanup and grammar acceptance gate → insertion and SQLite persistence. Cleanup runs during long recordings. Failures return the last safe text; they must not lose or silently truncate content. Keep queues bounded, cancellation explicit, and lifecycle operations idempotent. Audio callbacks must not allocate, lock, log, or invoke Swift concurrency.

Use constructor injection, typed contracts, declarative views, and focused files. No force casts, unjustified unchecked concurrency, unrelated refactors, or stubs. Validate boundaries. Follow [dependency enforcement](tools/check-deps).

## Models and runtime facts

- ASR default: Nemotron 3.5 ASR Streaming 0.6B Q8_0 GGUF via audio.cpp, with Metal and 320 ms preferred input cadence. Native sessions stay resident between recordings.
- Cleanup: S1-mini by Superwhisper, Q4_K_M GGUF through llama.cpp in the XPC helper. Preserve the pinned prompt, deterministic settings, attribution, deadlines, and fallback behavior.
- Endpointing uses the RMS fallback with a 600 ms pause and 120 s segment cap. Speaker separation uses Nemotron 3 Diarization Q8_0 through audio.cpp on Metal. Grammar uses Harper through the Rust C ABI.
- The user controls the Codex model/reasoning settings. Do not change them or launch additional agents without authorization.

Sources: [profiles](Packages/L0-Core/Kernel/Sources/SuperflowKernel/Models.swift), [ASR assets](Packages/L1-Adapters/AudioCpp/Sources/SuperflowAudioCpp/AudioCppAsset.swift), [native runtime](Packages/L1-Adapters/AudioCpp/Sources/SuperflowAudioCpp/AudioCppRuntime.swift), [model manifest](Packages/L1-Adapters/ModelStore/Sources/SuperflowModelStore/Resources/model-manifest.json), [XPC decision](docs/adr/0007-xpc-inference-helper.md). Registry entries are not proof that a model is installed or verified.

## Design rules

Read [DESIGN.md](DESIGN.md) §0–§5 and the affected component section; Island work reads §8.18. Check stale examples against current tokens/APIs. Report material conflicts.

- Calm, restrained, neutral surfaces. Blue 600 is the semantic accent. Separate content through spacing and surface contrast, without decorative borders, shadows, gradients, or glow.
- Use `Tok`, `Ramp`, `AppType`, spacing and radius tokens. Align to the 4 pt layout grid and device pixels through `Pixel`. SF Pro UI roles are 12/13/15/28 pt; dynamic numbers use tabular digits and stable widths.
- Use shared controls from UIComponents and SF Symbols from Icons. Features do not introduce raw interactive controls, arbitrary fonts, cursor management, or new visual systems.
- Native blur/glass belongs to navigation and designated floating chrome. The Island is opaque black, attached to the screen edge, with no shadow. Only its designated text-fade masks use gradients.
- Motion communicates state, without bounce or decorative loops. Honor Reduce Motion, keyboard focus, VoiceOver, contrast, light/dark appearance, and minimum window size. Preserve documented functional animation exceptions.
- Change design only when requested. Inspect actual native UI for visual changes; compilation alone cannot prove layout or focus works.

## Read only what the task needs

| Question | Reference |
| --- | --- |
| Product scope and implementation phases | [PLAN.md](PLAN.md), relevant numbered section; historical proposals need verification |
| Current runtime evidence and unresolved work | [docs/STATUS.md](docs/STATUS.md), relevant [ADR](docs/adr/) |
| Visual specification | [DESIGN.md](DESIGN.md); [DESIGN-RULES.MD](DESIGN-RULES.MD) and [rebuild guide](DESIGN-REBUILD-GUIDE.MD) are subordinate historical references |
| Engineering workflow | [RULES.md](RULES.md), task-relevant sections |
| Active task plans and previous findings | [work/plan](work/plan/), relevant task under [agents](agents/) |
| Packaging, permissions, recovery | [architecture](docs/architecture/), relevant [runbook](docs/runbooks/) |
| Commands and module overview | [Makefile](Makefile), [README.md](README.md) |

Local skills are optional unless their invocation rules require them. Resolve these under `~/.agents/skills/` and read only the matching SKILL.md: `engineeringkit-skill-router/SKILL.md` for UI/backend routing, `principle-fix-root-causes/SKILL.md` for debugging, `principle-prove-it-works/SKILL.md` for direct verification, `benchmark-checklist/SKILL.md` for measured performance, and `technical-writing/SKILL.md` for documentation. Existing project rules outrank generic skill aesthetics. Never preload the catalog.

## Work and verification

1. Inspect Git state and the target implementation. Trace affected callers, contracts, and tests. Use `rg` and bounded reads. Expand on evidence; do not reread unchanged context.
2. Make the smallest complete change. For substantial work, keep one concise plan and record useful decisions/results as RULES.md requires. Skip optional artifacts unless required or needed to resolve uncertainty.
3. Run affected package tests with `swift test --package-path <package>`. Add behavioral regression coverage for meaningful failures. Check connected packages when contracts change. For UI, inspect relevant native states; for pipelines, run affected goldens/integration tests; for performance, measure the real workload.
4. Run required gates after stabilization. Repeat passing checks only when changes invalidate them. Documentation edits need reference/consistency/diff checks, not application builds. `make verify` remains the full phase/release gate; `make lint` checks architecture and forbidden patterns. Never bypass a failing hook or weaken a check.
5. Review the actual diff. Fix task-related failures; report unrelated ones without modifying another worker's changes. Stop when behavior and applicable checks pass.
6. Commit and push each coherent change directly to main, using explicit owned paths and a specific 6–12-word message. Never mix another worker's edits into the commit. Stop on a rejected push; never force, pull, merge, reset, or rewrite without the permission required by GIT-SKILLS.md. Leave unrelated dirty files alone.

Report the result, checks, limitations, and commit status briefly. Never claim unrun checks, unmeasured behavior, or a clean shared tree without evidence.



# DESIGN.md: Superflow

**Audience:** AI coding agents building the app.
**Status:** the spec. If code and this file disagree, the code wins, then fix this file in the same change.
**Rule zero:** your default output is AI slop. Treat every instinct (cards inside cards, borders, gradients, glow, emoji, rounded-everything, generic icons, centered hero blocks) as wrong until a rule below says otherwise. Numbers are the spec. When asked for "sharper" or "smoother", tune numbers. Never replace the system and never add effects.

---

## 1. Color

Surfaces separate by luminance step, never by stroke. Every color is a token in `DesignSystem`. No hex outside it.

### 1.1 Surface ladder

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#F4F4F4` | `#0A0A0A` | canvas, page bar, list panes |
| `surface` | `#FFFFFF` | `#171717` | cards, dialogs, hovered list rows |
| `well` | `#EDEDED` | `#0F0F0F` | inset fields and tracks inside a card |
| `control` | `#EBEBEB` | `#1F1F1F` | buttons, selected rows, menu rows, dialog fields |
| `controlHover` | `#E3E3E3` | `#262626` | hover, menu panels |
| `controlPressed` | `#DADADA` | `#2E2E2E` | pressed, tracks, unlit pixels |
| `field` | `#EAEAEA` | `#101010` | search and fields on the canvas |
| `island` | `#000000` | `#000000` | the Island body only |

Washes (translucent backdrops only): `wash` black 5% / white 7%, `washStrong` black 9% / white 12%.
Scrims: `modalScrim` black 28% light / 55% dark. `scrim` black 18% (command palette).

**Field rule:** a field is always lighter than the surface it sits on. Dialog fields use `control`. Canvas fields use `field`. Never darker than the parent.

### 1.2 Text

| Token | Light | Dark |
|---|---|---|
| `text` | `#0A0A0A` | `#FAFAFA` |
| `text2` | `#666666` | `#A3A3A3` |
| `textAction` | `#2E2E2E` | `#E5E5E5` |

Two levels only. There is no `text3`. `textAction` is for text links, hover promotes to `text`.

### 1.3 Accent: blue 600, the only brand color

`accent #2563EB` · hover `#1D4ED8` light / `#3B82F6` dark · pressed `#1D4ED8` · `accentText #2563EB` / `#60A5FA` · `accentSoft #DBEAFE` / `#2563EB @17%` · `accentFill #DBEAFE` / `#2563EB @50%` (download fill) · `onAccent #FFFFFF`.
Nothing darker than blue 700, ever. **One accent-filled element per view.**

### 1.4 Pixel ramps

`Ramp.blue` (5 steps, index 0 to 4): light `E9E9E9 · DBEAFE · 93C5FD · 2563EB · 1E3A8A`, dark `171717 · 172554 · 1E3A8A · 2563EB · 60A5FA`. Use `[1]` and `[2]` for quiet or silent pixels, `[3]` for body, `[4]` for tips and heads.
`Ramp.heat` (activity graph, 4 steps): light `DBEAFE 93C5FD 2563EB 1D4ED8`, dark `1E3A8A 1D4ED8 2563EB 60A5FA`. **Zero activity is a gap, never a color.**
Diff highlight: `diffStrong` `#93C5FD`/`#1D4ED8` (removed or rewritten), `diffSoft` `#DBEAFE`/`#1E3A8A` (polished), `diffInk` `#0A0A0A`/`#FFFFFF` (text on strong).

### 1.5 Status and vendor

`statusOK #16A34A`/`#4ADE80`, `statusBad #DC2626`/`#F87171`. Status hues live only in dots, pixel marks and the failed badge.
`brandNvidia #87D501`. The one non-blue hue, only inside the NVIDIA mark. Vendor marks are bundled assets, never fetched, never recolored.

### 1.6 Do and don't

| Do | Don't |
|---|---|
| Separate layers by one surface step | Draw a border, hairline, `Divider()` or outline |
| Use blue 600 for the primary action, active state, focus and the pixel ramp | Introduce a second brand hue, purple, teal, orange accents |
| Show Active in blue (`accentSoft` + `accentText`) | Use green for Active |
| Keep text at `text` / `text2` | Add a third grey, or tint text with the accent |
| Use alpha washes only over blur | Stack opacity layers to fake depth |
| Let dark mode stay near-black with small steps | Go pure black on content or lift the canvas gray |
| Render zero data as a gap or dust | Fill empty data with a color |

---

## 2. Anti-slop rules

If a screen could belong to any other dictation app, redo it. Reject on sight:

1. Strokes, outlined cards, borders on fields, badges or buttons.
2. Gradients, glow, shimmer, shadows on content. (The only gradient file is `EdgeFade`, an alpha mask on text.)
3. An icon inside a circle, square or box. Icons are bare SF Symbols.
4. The empty-state stack of icon, bold title, grey sentence, pill button. Empty state is the pixel stop + a title + one sentence naming the next action.
5. The page-header stack of title, subtitle, three buttons, search, filter. Search lives in the bar or the list header, one primary action per page.
6. A card inside a card. A list of cards. Per-row cards.
7. Info-icon footnotes, help paragraphs under settings, repeated privacy lines.
8. Middle-dot chains in meta text, trailing arrows, leading chevrons in buttons, exclamation marks, ALL CAPS eyebrows.
9. A full-width progress bar, a spinner, a skeleton shimmer.
10. Sparkle icons for AI. Emoji. Third-party icon sets.
11. Hover-only controls that keyboard and VoiceOver users cannot reach.
12. Floating carets, edge accents or lines that align to nothing.
13. System glass on menus and dropdowns. Native-looking is solid, from our own surface ladder.
14. Centered text blocks and big hero sections inside a utility app.
15. More than three cards per Settings tab, more than five rows per card.

**Test:** swap the logo. If it still looks like the same app, it is slop.

---

## 3. Brand language: blue pixels

**One boldness budget: the pixel.** The full stop that ends every page title is the identity. Everything else is quiet, dark and disciplined. If a screen has a second memorable element, delete one.

- **The pixel stop:** 5 × 5 cells at 1.5 pt (7.5 pt) ends every page title. Dialog headers use the 7 × 7 disc at cell 2. Empty states use 11 cells at 4 pt (3 pt in panes). Never resized per screen.
- **Cells:** square, whole device pixels, `antialiased: false`. Common sizes: 2 pt cells with 1 pt gap (Island meter), 3 with 1 (countdown, barcodes), 4 with 2 (waveform tape, heat graph).
- **Dither, never gradient:** transitions between tones use a checker of two flat colors. Edges dissolve through density steps (0.8, 0.55, 0.32, 0.14).
- **Dust:** empty or inactive positions draw a 1 pt dot in `controlPressed`, so silence reads as a dotted line, never a dead slab.
- **The head:** the newest or current cell is white (`text`): scan line, newest meter column, today's cell, the playhead.
- **Pixel badges:** `NotchedRect` (2 pt stepped corners, no radius, no stroke) + a 1 pt-cell bitmap mark + 12 pt text. Active = `accentSoft`, blue pixel disc. Same notched shape for trigger chips and dictionary terms.
- **Bitmaps:** hand-drawn from `#` strings: check, lock, spark, flame, arrow-up, arrow-right, dot, disc, mic. Add new marks the same way.
- **Vendor marks:** the NVIDIA eye (green), the S1-mini plate (clipped tile) and the Hugging Face mark sit in 32 pt `control` tiles, 8 pt radius.
- **Display face:** Serif Vinci Italic, only in page titles (28) and onboarding titles (40), never upright, never below 28. Section titles are `AppType.title`.

---

## 4. Type

One UI face: SF Pro through `AppType`. No raw `.font(.system(size:` outside `AppType`, `UIComponents`, `Icons` and SF Mono.

| Role | Size / weight | Tracking |
|---|---|---|
| `caption` | 12 / 350 | 0 |
| `body` | 13 / 350 | −0.1 |
| `label` | 13 / 500 | −0.1 |
| `reading` | 15 / 350 | −0.2 |
| `title` | 15 / 500 | −0.2 |
| `metric` | 28 / 500, tabular | −0.6 |

Weights 350 (read) and 500 (scan) only. Sentence case. Every changing number is tabular with reserved width. SF Mono 12/13 for code, shortcuts and identifiers. Prose measure ≤ 720. Time is 12-hour by default (`9:43 PM`), with a Settings switch for 24-hour. Time comes first, the day is a quieter second element (`Yesterday`, `Fri`, `Oct 21`). Never a date as a title.

---

## 5. Space, shape, size

- **Grid:** 4, 8, 12, 16, 20, 24, 32, 48, 64. Anything else needs a written reason. Page padding 32, section gap 32, card padding 20 (dense lists 8 + 12), one left edge at 32.
- **Radii:** card 16, nested 12, field 8, chip 6. Buttons and toggles are capsules. Nested radius = outer minus padding.
- **Control heights:** text buttons 24 or 28 (32 only in dialogs and the Add button). Search 32. Row icon button: 12 pt glyph in a 28 pt target, pulled out so the glyph, not the target, sits on the edge.
- **Rows:** history/list 56, dashboard recent 48, usage 40, dictionary/shortcut entries 44, settings 48, models 64.
- **Whole pixels:** every origin, size and offset goes through `Pixel.snap`; symmetric shapes through `snapEven`. A half-pixel edge is a bug.
- **Icons:** SF Symbols at 9, 12, 14 or 16. Regular weight. Row app icons 16, wings 20. Each icon has an accessibility label if icon-only.

---

## 6. Components

All live in `UIComponents`. Features compose them and never build raw controls. Raw `Button` and `onTapGesture` exist only there.

- **Button:** flat capsule. Primary = accent, secondary = `control`, quiet = text only, link = `textAction`. A disabled primary renders as a quiet control, not dim blue. Press scale 0.98.
- **Card:** `surface`, radius 16, padding 20, no stroke.
- **Menus and dropdowns:** one `MenuHost`, one `MenuLayer` above content and below dialogs. Solid `controlHover` panel, radius 12, 4 pt inset, 32 pt rows, one sliding highlight, prefix icon on every item, destructive item red and separated by air (never a line). Anchored to the trigger's real frame, flips up near the bottom, clamps at the edges. Opens with scale 0.96 + fade from the trigger corner, closes in 120 ms. Arrows, Return, Esc.
- **Dialogs:** `DialogLayer` at the root, scrim covers the title bar. Panel 480 wide, padding 24, radius 16, header = pixel disc + title + one-line subtitle. Fields 32 tall, lighter than the panel, editor fixed 128. Footer: Cancel (secondary) + confirm (primary), both 32. Esc cancels, ⌘Return confirms, first field focused, confirm disabled until valid. `.sheet`, `.alert`, `.popover` are banned.
- **Segmented:** capsule track, sliding thumb, three levels (canvas, card, dialog) so it always differs from its parent.
- **Toggle:** 40 × 24 track, 20 knob (26 pressed), Blue 600 on, haptic on flip.
- **Slider:** 280 + 64 readout. Track is a row of 2 × 4 pt ticks on a 4 pt pitch; passed ticks rise to 8 pt in blue, the three nearest the thumb run hot with a dither, the thumb is a 2 pt scan line. A spring drives the thumb at display rate. Value snaps, thumb settles, haptic per step.
- **Rows:** hover = `control` fill, selected = `control`, no dividers, no floating caret. Hover controls are also in the accessibility tree and focusable.
- **Settings row:** bare 14 pt glyph in a 20 pt column, 12 gap, label `AppType.label`, 48 tall, no help text.
- **Toast:** system glass capsule, 40 tall, one quiet action.
- **Glass** exists only on the sidebar, toasts and the command palette.

---

## 7. Surfaces

- **Shell:** custom `HStack`, sidebar 220 (system blur) + detail on `bg`. Window 960 × 620, min 880 × 560. Route change is an opacity cross-fade only.
- **Sidebar:** seven rows, 32 tall, one sliding selection capsule. Status footer = 20 pt pixel mark + one word, no fill, `wash` on hover. Mark: disc (Ready, green dot), disc dithered (Basic cleanup), ring (problem), radial fill (Warming up).
- **Dashboard:** ledger card (four metrics), the month graph (1st of this month through the 15th of next, 4 pt gap, 12 pt between months, today = one white pixel, empty days gap, future days dust, hover readout replaces the subtitle), Recent dictation (zero-word sessions hidden), usage barcodes.
- **Recent dictation row:** app icon, one faded line, `time + day`, duration, words. Hover reveals Play, Copy, ⋯. Menu: Play audio, Retry transcript, Extract audio, Delete transcript. Failed or cancelled rows always show a badge and **Retry transcript**. Delete has a 6 s undo.
- **Cleaned vs Raw:** the highlight is the product. Strong highlight = removed (Raw) or rewritten (Cleaned), soft = polished. Highlights sweep in over 14 steps on toggle. A legend shows counts and a 10-cell edit meter, and the first four changes are listed (old struck through → new). Breathing room: 20 above the text, 20 below, `lineSpacing` 6.
- **History:** list 320 + detail. Header copy and delete are 12 pt glyphs in 28 pt targets. Detail order: header, audio, diff transcript.
- **Meetings:** Live | Past tabs, list stays visible. List rows 72 with a 96-cell speaker barcode. Zero-word meetings collapse under "No speech". Detail: header + Copy as Markdown, audio bar with the pixel tape, clickable strip, turns with a 120 pt speaker column. The turn being spoken is highlighted while audio plays. Timestamps seek and play.
- **Models:** pipeline strip (Mic → Noise → Speech → Cleanup → Your text), a node lights when its model is in use. Two groups (Dictation, Meetings), rows 64 with brand tile, name, subtitle, size, pixel badge, ⋯. Active is blue.
- **Shortcuts and Dictionary:** scope toggle, then search + ⋯ + the one accent Add button, 16 below the toggle. Entry rows show trigger chip → pixel arrow → result, menu on hover. Terms are notched chips in a flow layout. Bundled terms collapsed. "Try it" playground reuses the diff highlight. Shortcuts empty state and shared scope stay honest.
- **Island:** a hardware notch extended. Opaque black, no material, no shadow. Silhouette via true quarter-circle Béziers. Phases: idle, hover, listening (hold or latched with a rolling clock), processing (the 32 × 8 pixel sweep), landed (pixel check), cancelled (pixel dissolve, 6 s undo with a drain countdown), failed ("Not pasted." + Paste again + Copy), recent/history, meeting (barcode wings, panel), notes. Meter: symmetric envelope for dictation, scrolling barcode with a white head for meetings, silence = dotted line in `Ramp.blue[2]`.

---

## 8. Motion

Motion explains and never decorates. State-driven only. Nothing bounces, nothing loops, **except** the allowed indeterminate marks (Island sweep, wait cells, warming mark, row "Transcribing" cells, rolling clock). Reduce Motion renders the end state.

| Event | Spec |
|---|---|
| hover in / out | `easeOut 0.10` / `0.22` |
| press | scale 0.98 (0.92 for controls ≤ 28) |
| route / tab content | `easeOut 0.18` |
| sidebar pill, segmented thumb, expand | `smooth 0.30` |
| menu open / close | `smooth 0.20` / `easeOut 0.12` |
| toggle | `snappy 0.22`; knob stretch `snappy 0.12` |
| readouts | `.numericText` with `snappy 0.15` |
| entrance stagger | 35 ms per row, 6 pt rise, critically damped |
| graph and tape reveal | 14 whole steps, once per launch |
| diff highlight sweep | 14 steps over 280 ms |

**Island:** exact critically damped or lightly underdamped springs solved per display frame (60 to 120 Hz), width leading height so the shape reads as a wave. Opening ω ≈ 14 to 12 (ζ 0.80 to 0.84), closing ω 22 to 20 (ζ 1), card to card ω 18 (ζ 0.88), wings ω 30 (ζ 0.86). Retarget keeps position and velocity, so interruptions never restart. Content is laid out once at its final size and revealed by the moving silhouette: outgoing fades first, incoming follows late with a 5 pt rise. **No blur-in or blur-out.** The frame loop stops at rest.
Never `linear`, `easeInOut` or `bouncy`. Never animate something that carries no information.

---

## 9. Loading, empty and error states

Every state is designed. No spinner, no bar, no shimmer.

- **Waiting, indeterminate:** three 2 pt cells stepping every 160 ms (rows, wings), or the 32 × 8 pixel sweep (Island submitting, meeting saving), or the radial disc fill (sidebar warming).
- **Downloading:** the row fill is blue with a 16 pt dissolving pixel front. The row expands to a readout: rate in `metric` (no numeric roll), time left, and a pixel throughput strip (4 × 4 cells, newest column white tip). Bytes as "x of y". Row height never changes between states.
- **Verifying:** full fill, the word "Verifying".
- **Installed:** the fill fades out over 450 ms, the row returns to quiet.
- **Failed:** no red fill. The detail line states why, a failed badge and **Retry** sit on the right. Every failure offers a retry.
- **Countdowns:** an 18-cell pixel drain plus a tabular numeral. Whole steps.
- **Empty:** the pixel stop (11 cells) + one sentence naming the next action and its shortcut. Example data wears an `Example` badge and is replaced the moment real data exists.
- **No data in a graph:** dust and gaps, never a colored slab.
- **Success:** a pixel check that develops left to right in 4 steps, a one-shot dithered burst for milestones, a haptic where the platform has one.
- **Destructive:** delete first, offer a 6 s undo toast, remove files when it expires.
- **Privacy:** "Don't store transcripts" means nothing is stored, and the example states show.

---

## 10. Accessibility and input

- VoiceOver labels on every icon-only control, announcements on Island edges ("Listening", "Pasted", "Couldn't paste").
- Keyboard ring is ours: 2 pt accent, offset 2, shown only for keyboard navigation, never after a click or on open. System ring is disabled at four levels.
- Increase Contrast adds a 1 pt `ContrastStroke` (the only stroke) on cards and fields. Reduce Transparency swaps glass for `surface`.
- Pointer: hand on everything clickable through `clickable()`, arrow when disabled, I-beam in text fields.
- Shortcuts: ⌘1 to ⌘7 routes, ⌘F search, ⌘N add, ⌘K palette.

---

## 11. Process (mandatory)

1. **Declare tokens first.** List the surface steps, spacing, radii, type roles, control heights and glyphs a view uses. Use only those.
2. **Native before custom,** except where this file names a custom component.
3. **Build with token names.** No literals for color, spacing, radius or height outside `DesignSystem`.
4. **Delete** anything that carries no information and no affordance. Then delete one more thing.
5. **Verify by measuring:** 2× crops, dark and light, 400% on every edge you touched, `pixelAudit` silent, lint green, `make verify` green.
6. **Report honestly** what you could not verify. "Looks right" is not a result.

Lint fails the build on: strokes outside `ContrastStroke`/focus ring, gradients outside `EdgeFade`, hex outside `DesignSystem`, raw `Button`/`Toggle`/`Picker`/`Slider` in features, `.sheet`/`.alert`/`.popover`, weights above Medium, off-list icon sizes, `.animation(.linear/.easeInOut/.spring/.bouncy)`, `Divider()`, raw font sizes outside `AppType`, `Image("...")` outside `ModelMark`, `AVAudioPlayer` outside the two player files, files over 400 lines.

---

## 12. Review checklist

- [ ] No stroke, shadow, gradient or glow. Surfaces separate by step.
- [ ] Blue 600 only, one accent-filled element, Active is blue.
- [ ] Every icon is a bare SF Symbol at an allowed size. Every menu item has a prefix icon.
- [ ] Pixels are square, whole-pixel, dithered, with dust for empty and a white head.
- [ ] Every state exists: loading, empty, failed with retry, success, undo.
- [ ] Time reads like a person. Numbers are tabular and do not walk.
- [ ] Motion is state-driven, Reduce Motion works, the Island never blurs.
- [ ] Fields are lighter than their panel. Dialog Cancel and confirm are real buttons.
- [ ] The swap-the-logo test passes.


# Agentic Backend Pipeline: Build Spec

Goal: agents that reliably solve **hard backend work** (migrations, concurrency,
money, auth, data integrity) with as few moving parts as possible.

## The one idea

A model doesn't need a smarter process. It needs an **oracle**: a frozen,
executable definition of "done" written *before* any code exists. Everything
else is a loop that runs until the oracle says yes. Plan mode, tests, and spec
clarity all come out of that single mechanism.

## Principles

- KISS. Boring, proven tools. If a step doesn't catch a real failure, delete it.
- Orchestrator is plain code (a few hundred lines). No state machine library, no framework.
- LLMs only for judgment: plan, implement, review.
- Plan mode for non-trivial work, then **execute without asking permission**.
- Humans are pulled in only at the escalation points below, plus the merge gate for risky changes.

## Pipeline

```
Spec -> Plan + Oracle -> Implement loop -> Review -> Ship
        (full mode)      (until green)    (full)
```

One run = one `runs/<id>.json` file (mode, plan path, oracle results per
iteration, review output, tokens, time, outcome). That is the entire
observability story.

## 0. Mode

Two modes. No scoring.

- `quick`: single-file or obvious fix, UI tweak, copy change. Implement, run checks, ship. **No plan.**
- `full`: everything else. Plan + Oracle, review, the works.

The agent picks the mode. **Risk paths force `full` + `gated`.** List them once
in `pipeline.config` as globs: `migrations/**`, `**/auth/**`, `**/billing/**`,
webhook handlers, anything touching money or PII. One glob match, no heuristics.
Over-picking `full` costs tokens only. Under-picking is what the risk-path rule prevents.

## 1. Plan + Oracle (full mode)

One call to the strongest model. Output `plans/<id>.md` (target under ~600
tokens) plus **acceptance test files**.

### Plan template

```
# Plan: <title>
## Goal (2-3 lines)
## Non-goals
## Invariants (must always be true)
## Failure modes (retry, concurrent request, partial failure, bad input) and expected behavior
## Approach (a few lines, not a restatement of the spec)
## Steps (ordered; each has a Verify command)
## Files
```

### Backend prompt checklist (content for the planner, not extra stages)

The planner must explicitly address, where relevant:
- transaction boundaries and isolation level
- idempotency keys and safe retries
- locking / race conditions between concurrent requests
- ordering guarantees and partial-failure behavior
- timeouts and external call failure
- migration safety: lock time, backfill, rollback
- indexes and query plans for new queries (no N+1, no unbounded reads)
- authz checked on every path, not just the happy one

### Oracle rules

- Acceptance tests are written **now**, from the spec, before implementation.
- Orchestrator runs them first and confirms they **fail (red)**. A test that passes before any code exists is vacuous or the work is already done. Flag it.
- Every invariant and every failure mode gets at least one test.
- Concurrency and idempotency get a **real parallel test** (N simultaneous requests), not a comment or a mock.
- Run against **real Postgres**, ephemeral per run (Neon branch or local container). Do not mock the database for backend logic.
- Migrations: test forward on a realistic populated snapshot, and test rollback.
- Once committed, these files are **frozen**. The orchestrator rejects any implementer diff that touches them.
- If a requirement can't be expressed as a test, the **spec is ambiguous**. That's escalation trigger #1.

After this step passes, **execute without asking permission**.

## 2. Implement loop

- Isolated git worktree and branch: `agent/<id>`.
- Input: spec, plan, oracle test paths, `AGENTS.md` (conventions), curated relevant files. Never the whole repo.
- Loop: edit -> run oracle + typecheck + lint + existing suite -> read **trimmed** failure output -> fix. Repeat until green.
- Run each plan step's Verify command as you go so errors surface early, not at the end.
- Frozen tests are read-only. Plan deviations are allowed only inside Goal and Non-goals; log one line per deviation.
- `quick` mode: same loop, no oracle, just the existing checks.

### Stuck rule (the only retry logic)

If the same failure signature appears twice in a row, stop that approach and
**replan once** (fresh planner call with the failure output). If it gets stuck
again, escalate. No other retry counters.

## 3. Review (full mode only)

- One reviewer, **fresh context**: spec + plan + diff only, never the implementer's reasoning. Different model than the implementer if available.
- Scope: only what tests can't prove. Security, authz gaps, data-loss paths, race conditions the oracle didn't cover, perf traps, and scope creep against Non-goals.
- Output structured JSON: `{ verdict, issues: [{severity, file, line, problem, fix}] }`.
- `blocker` or `major` goes back to the implementer **once**. Still failing => escalate.

Automatic flags (plain code, no LLM), sent to the reviewer as blockers to justify:
- any attempt to change a frozen test
- any deleted or weakened existing test
- any new dependency
- any file changed outside the plan's Files list

## 4. Ship

- Fetch and rebase on base. If base moved, re-run all checks.
- Ungated (`quick`, non-risk `full`): auto-merge when green and review is clean.
- **Gated (risk paths): open a PR, do not merge.** PR contains the plan, oracle results, review output, and a 5-line "what to check" summary. A human merges. Autonomy covers execution. Humans own irreversible merges.
- Git rules, non-negotiable (shared repo, multiple agents):
  - commit after every task, messages 6-12 words, direct and human
  - check status and pull before pushing
  - never `git reset` or `git restore` without explicit human permission
  - if no repo or remote is configured, ask before committing

## Guardrails

- **One budget per run:** max tokens and max wall-clock. Hit either => stop, save state, escalate.
- Writes only inside the worktree. Destructive commands blocked.
- Never connect to a real production database. The oracle DB is always ephemeral.
- Secrets never logged or committed.

## Escalation (the only times a human is asked)

1. A requirement can't be turned into a test (ambiguous spec).
2. Budget hit, or the stuck rule failed twice.
3. Irreversible action needed (dropping data, force-push, real-data migration).

Escalation output: what was tried, current state, the one specific question,
and a recommended default answer.

## Evals (what separates a design from a system)

`evals/` holds **15-20 real past tasks**: spec, repo commit, and **held-out
acceptance tests the pipeline never sees**.

- `bun run evals` runs the pipeline on all of them and reports pass rate, tokens, time, escalations.
- Rerun on any change to prompts, models, or rules. A change that lowers the pass rate doesn't ship.
- Include a few genuinely hard backend cases: a race condition, a migration on a populated table, an idempotent webhook, a query perf regression.

## Build order

1. Orchestrator skeleton: run.json, worktree, check runner (trimmed failures), ship. `quick` mode end to end.
2. Implement loop with budget and stuck rule.
3. Plan + Oracle: red check, frozen-file enforcement, ephemeral Postgres.
4. **First 3 eval tasks now**, before going further.
5. Reviewer + automatic flags.
6. Gated PR path.
7. Fill out evals to 15-20.

Add nothing new until evals show a failure class that it would fix.