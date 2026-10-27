# Alignment — what the design says vs. what the code does

**Verdict: 77% aligned.** Grade: **B−**. The bones are right and provably right — custom shell, no strokes, monochrome bare icons, one accent, the pixel identity, a real deficit-free component layer. What holds it out of the 90s is not taste, it is **discipline**: the app runs **two UI typefaces at once**, one behaviour the third pass specified was never wired, and `DESIGN.md` — the document that claims to be the spec — was never rewritten, so it now contradicts the code on the shell, the table, the token ladder and the icon rendering.

Nothing here is a matter of opinion. Every claim has a file and a line.

---

## How this was measured

| Document | What it is | Authority |
|---|---|---|
| `DESIGN.md` | the base spec, on disk at repo root | base |
| `DESIGN-RULES.MD` | the pre-rebuild rulebook | superseded where it conflicts |
| `DESIGN-REBUILD-GUIDE.MD` | Pass 1 (ground-up rebuild) | overrides `DESIGN.md` |
| *(pasted)* Pass 2 (structure) | shell, bar, menus, controls, Settings | overrides Pass 1 |
| *(pasted)* Dashboard lower half | the third pass | overrides Pass 2 |

`DESIGN.md`'s own header: *"If code and this document disagree, the code wins — then fix this document in the same change."* Every pass repeats the same instruction. **That instruction was not followed** (see §6), which is why the smallest score on this report is the documentation's.

Method: read the token layer, the whole `UIComponents` layer, all six feature surfaces, the shell, and the onboarding; then ran the specs' own mechanical checks plus the repo's `tools/lint-forbidden` (which **passes**). 1460 non-test Swift files were scanned; the UI surface is ~40 files under `Packages/L4-UI` and `App/SuperflowApp/Sources/SuperflowAppCore/Windowing`.

---

## Scorecard

| Area | Weight | Score | Why it scores there |
|---|---|---|---|
| Tokens & colour | 10 | **96%** | `Colors.swift` is the Pass-1 ladder verbatim. Nothing ad-hoc. |
| **Type** | 16 | **45%** | Two UI faces in the same row. The single worst outcome in the app. |
| Borders, surfaces, shadow | 8 | **97%** | Zero gradients, zero shadows, strokes exist only in `Surfaces.swift`. |
| Icons | 8 | **92%** | Bare, monochrome, four sizes, one enum, launch-time validation. One wrong symbol. |
| Shell & sidebar | 10 | **88%** | Built exactly to Pass 2, one Reduce-Motion hole. |
| Page chrome & alignment | 12 | **84%** | Correct 52/60/32 geometry; two row-inset ambiguities the spec itself created. |
| Controls | 8 | **92%** | Native slider wrapped, no popover, no focus ring, keys handled. Two disabled opacities. |
| Dashboard | 8 | **84%** | All three components land; one behaviour unwired, one clipping bug. |
| Onboarding & canvas | 10 | **88%** | Four steps, one field, the flight chain, tested. Two full stops at two sizes. |
| Motion | 6 | **88%** | Token-perfect; one unguarded animation. |
| Pointer | 4 | **100%** | Two-layer hand, lint-enforced. This one is finished. |
| Accessibility | 8 | **85%** | Labels and rings everywhere; Increase Contrast misses fields and buttons. |
| Copy | 2 | **95%** | Sentence case, verb-led, no dotted chains, no exclamation. |
| **Docs & enforcement** | 16 | **35%** | The lint is real and extended. `DESIGN.md` is not. |

Weighted: **77%**.

---

## 1. The five things that cost the most

### 1.1 Two UI typefaces, in the same row (Type: 45%)

The app resolves **78** `Typography.*` call sites (Albert Sans) and **52** `.system(size:)` call sites (SF Pro) across the UI. They are not in separate rooms:

- `Rows.swift:146` — an `EntryRow` draws its **trigger** in `Typography.body` (Albert Sans 13) and its **result** in `.system(size: 13, weight: .medium)` (SF Pro 13 Medium). One row, two faces, one line.
- `Surfaces.swift:218` — `SectionHeader` title is `.custom(AppFont.baseName, size: 15)` (Albert Sans **Regular**); the `Metric` beside it (`Indicators.swift`) draws its label in `.system(size: 12)` (SF Pro). The Dashboard puts them side by side.
- `MainWindowRootView.swift:202` — a sidebar row is SF Pro 13; the page subtitle under it, two inches away, is Albert Sans 13.

Why this is the top defect: a typeface change inside one component is not a nitpick, it is the thing your eye reads as "unfinished" before it can name anything. It also means **neither** instruction was followed — `DESIGN.md` §9 says Albert Sans is the only UI face; Pass 1 §R5 says SF Pro is the only UI face. The code does both, and no lint rule exists that could have caught it.

### 1.2 The final pass's Fn behaviour was never wired (Dashboard: 84%)

Pass 3 §12.2 rule 4 is explicit: `HoldToTalkHint` is deleted and the keycap *"also goes down for real when the user actually holds Fn (`vm.isFnHeld`, the session-state stream added in pass 1)"*. §12.4 shows `CleanupCard(mode:fnHeld: vm.isFnHeld)`.

`rg isFnHeld` over `Packages` and `App` returns **nothing**. `DashboardView.swift:32` and `:35` construct `CleanupCard(mode:)` only, so `fnHeld` is permanently `false` (`DashboardCleanup.swift:199`) and the keycap animates only in the example. The signature was built; the wire was not.

### 1.3 The 12-month graph clips its own last row (Dashboard: 84%)

`ContributionGrid` sizes its frame from an **assumed** width and draws from the **measured** one:

- `ContributionGrid.swift:157` — `let available = Space.pageMaxWidth - Space.pagePadding * 2` → **816pt**, always.
- Reserve: `gridHeight` = `round((816−156)/53)·7 + 18` = **102pt**, at every window size.
- Draw: `pitch = measuredCell + 3`, so seven rows need `7·cell + 18`.
- Clip condition: `cell > 12`, i.e. content width **> ~792pt**, i.e. a window **≥ ~1076pt** wide.

Past roughly 1076pt of window, the bottom row of the year graph is cut by the canvas. At the default 960pt it does not clip — it just floats with ~17pt of dead space under the last row instead of the intended spacing. The same assumed constant at `:201` also maps `onContinuousHover` to the wrong column at any width other than 816, so the tooltip reports the neighbouring day.

### 1.4 Two pixel full stops at two different sizes (Onboarding: 88%)

The spec makes the disc *the* identity mark and the same object as every title's period (`GUIDE §1.3`, `DESIGN.md §13.7`).

- Page titles: `PixelStop(cells: 5, cell: 1.5)` → **7.5pt** (`Surfaces.swift:40`).
- Onboarding's landed disc: `cells = 7`, `landedCell = 2` → **14pt** (`PixelDiscFlight.swift:29–32`).

The same brand mark, twice the size, on the one screen where the user is being introduced to it. §13.7 offers 5 *hero* / 7 compact — hero is the right choice for a 40pt title, and it is the size the rest of the app uses.

### 1.5 `DESIGN.md` is stale, and so is the ADR index (Docs: 35%)

Both Pass 1 §2 and Pass 2 §2 required `DESIGN.md` to be rewritten **in the same change**. It still says:

| `DESIGN.md` says | The code does |
|---|---|
| §4 Shell: `NavigationSplitView`; Target: macOS 26+ | custom `HStack`; every `Package.swift` is `.macOS(.v15)` |
| §5.2: `.searchable`, system `.toolbar`, `ToolbarItem`, `Table` | `SearchField`, `PageBar`, `ActionMenu`; no `Table` anywhere |
| §6.1/§6.2/§17.1: `bg #FFFFFF`, `card`, `raised`, `hover`, `pressed`, `text.3` | `bg #F4F4F4`, `surface`, `well`, `control`, `text2` — two text levels, no `text.3` |
| §4: icons "hierarchical rendering" | `.monochrome`, and `hierarchical` is lint-forbidden |
| §10: window min 960×640 | 880×560 |

`docs/open-questions.md` compounds it: it still asserts *"app UI follows `DESIGN.md` and renders hierarchical SF Symbols"* — the exact line Pass 2 §5.2 overturned — and still asks for a content-width token for a 900pt column, which `Layout.narrow = 640` already answers.

Only §13.7 and §17.6 of `DESIGN.md` were actually updated. The document that the project calls "the spec" now describes a different app than the one in the repo.

---

## 2. Defect register

| # | Where | Doc says | Code does | Severity |
|---|---|---|---|---|
| 1 | Whole UI | Guide R5: SF Pro only. `DESIGN.md` §9: Albert Sans only | 52 `.system(size:)` + 78 `Typography.*`, **mixed inside single rows** (`Rows.swift:146`, `Surfaces.swift:218`) | **Critical** |
| 2 | `DashboardView.swift:32,35` | Pass 3 §12.2/§12.4: `fnHeld: vm.isFnHeld` | No `isFnHeld` exists; keycap never reacts to Fn | **Critical** |
| 3 | `ContributionGrid.swift:154–158, 201` | §6.12: whole-cell grid on canvas | Height/hover sized from an assumed 816pt; last row clipped ≥ ~1076pt windows | **High** |
| 4 | `Surfaces.swift:40` vs `PixelDiscFlight.swift:29–32` | §13.7 one full stop | 7.5pt on pages, 14pt in onboarding | **High** |
| 5 | `MainWindowRootView.swift:184` | §14: Reduce Motion renders final state | `.animation(Motion.slide, …)` with no `reduceMotion` guard — the pill still slides | **High** |
| 6 | `DESIGN.md` §4/§5.2/§6/§9/§17.1/§18 | Guide §2, Pass 2 §2: rewrite it in the same change | Not rewritten; contradicts the code on six systems | **High** |
| 7 | `docs/open-questions.md` | Pass 2 §5.2: monochrome | Still asserts hierarchical; stale content-width question | Medium |
| 8 | `MenuBarContentView.swift:17,32,49`; `IslandPanelController.swift:202,206` | `DESIGN.md` §2: "No `Divider()`"; §18 checks for it | 5 `Divider()` calls; the lint's stroke pattern omits `Divider()` so they pass silently | Medium |
| 9 | `Glyph.swift:60` | Pass 2 §5.2: `timeSaved = "clock"` | `timeSaved = "timer"` (and a separate `clock` exists) | Low |
| 10 | `Sliders.swift:100,142` | One disabled treatment | raw `0.35` where everything else uses `Opacity.disabled` (`0.4`) | Low |
| 11 | `ContributionGrid.swift:174` | §10 grid: 4·8·12·16·20·24·32·40·48·64 — anything else is a bug | legend swatches `11×11`, and not equal to the graph's own 9.5pt cell | Low |
| 12 | `OnboardingShell.swift:82` | Guide §8.2: label change must not resize the button | `minWidth: 140` still lets it grow at "Open Superflow" | Low |
| 13 | `Card`/`ProgressRow` only | §15: Increase Contrast outlines **fields, buttons and cards** | `contrastStroke` applied to cards and progress rows, not to `AppField`, `AppTextField`, `SearchField` or any button | Medium |
| 14 | `Indicators.swift` `NoticeBanner` | §12.3: error state is `ContentUnavailableView` + retry | Undocumented banner component used for every error (Dashboard, Settings, Meetings, Onboarding) | Medium |
| 15 | `CommandPalette.swift:109` | §17.1: no literals outside tokens | `Color.black.opacity(0.18)` scrim — the one non-token colour in the app | Low |
| 16 | `Components/` | §5.1 rung 4: custom components need a written spec first | ~12 components ship with no spec entry: `NoticeBanner`, `ProgressBar`, `AppField`, `AppTextField`, `AppTextEditor`, `PracticeField`, `IconButton`, `RowButton`, `KeyValueRow`, `GlassSurface`/`GlassCapsule`/`GlassGroup`/`FloatingPanel`, `TextDiff`, `WaveformView` | Medium |
| 17 | `tools/lint-forbidden` | §18 / Pass 2 §13 | No rule for `Divider()`, off-grid spacing, `help:` on `SettingRow`, or `.system(size:)` outside `Typography` — the last one is why defect 1 survived | Medium |

---

## 3. Where the instructions contradict each other

These are not code defects; they are places where a coding agent could not have satisfied both documents. They belong in `DESIGN.md` as decisions, not left as traps.

| Conflict | Pass 1 / 2 say | `DESIGN.md` says | Code chose |
|---|---|---|---|
| UI typeface | SF Pro for everything (R5) | Albert Sans (bundled) + Serif Vinci | **both**, inconsistently |
| Progress dots | Guide §6.11: `20 / 6`, gap 6 | §17.6: `16 / 4`, gap 8 | `DESIGN.md` — correct call, `20` is off the 4pt grid |
| List-row icon edge | §14.1 contract: icons at x = 252 (= 32 from the pane edge) | §7.5 snippet: `padding(.horizontal, 12)` inside a 32pt page | Pass 2's **snippet** (icons land at 44). History passes because 24 + 8 = 32. |
| Sidebar blur | Pass 2 §6.3: `NSVisualEffectView(.sidebar, .behindWindow)` | §11.5: `.regularMaterial` | Pass 2 |
| Window min | 880 × 560 | 960 × 640 | Pass 1/2 |
| macOS target | Pass 1: macOS 26 assumed | §4: macOS 26+ | **macOS 15** with `#available(26)` gates |
| Custom components | allowed where specified | rung 4: "needs a written spec added here first" | neither — 12 undocumented components |

---

## 4. Cleared — and this is why 77% is not lower

- **Borders, gradients, shadows.** `rg` for `LinearGradient|RadialGradient|MeshGradient|EllipticalGradient`, `\.shadow\(`, `\.border\(|strokeBorder|\.stroke\(` outside `Surfaces.swift`: **zero, zero, zero.** Separation is the surface ladder and spacing, exactly as Pass 1 §R2 demands.
- **Icons.** One `Glyph` enum, `.monochrome` everywhere, no enclosures, no `*.circle`/`*.square` variants, no third-party family, sizes confined to 14/16/12/9 by lint, `validateGlyphs()` at launch. `sparkles`/`wand.and` appear only inside a comment that documents their absence.
- **Shell.** `NavigationSplitView`, `.toolbar`, `.searchable`, `ToolbarItem`, `.popover`, `isMovableByWindowBackground = true` (main): **all gone**, and lint-enforced. Sidebar is 220pt native blur over a non-opaque window, first row at y = 52, 32pt rows 2pt apart, fixed 20pt icon column, one `wash`/`washStrong` capsule that slides via `matchedGeometryEffect`. Defects D1, D2 and D5 from Pass 2's screenshot list are structurally impossible now.
- **Page chrome & the alignment contract.** Bar 52pt, title at y = 60, every page on one `pageWidth` primitive with `Layout.pad = 32` — so the search field, title, cards and graph share one left edge on all six routes. `⌘1–⌘6`, `⌘F`, `⌘K`, `⌘⌥S` all exist as commands.
- **Controls.** `Segmented` with a sliding thumb, `AppToggleStyle` (38×22, knob 18→22, 32pt hit), `Dropdown`/`ActionMenu` in one root `MenuLayer` with no arrow chrome, no sky-blue ring (`.focusEffectDisabled()`), arrow keys, Return, Escape and outside-click; `TimingSlider` wraps Apple's native `Slider` (fixed 280 + 64 tabular readout); `AppStepper`; `KeyRecorder`. Raw `Button`/`Toggle`/`Slider`/`TextField` in feature packages: zero.
- **Pointer.** `clickable()` is two layers (`pointerStyle` + an AppKit cursor rect) and is the only path — lint-banned anywhere else. This one is done.
- **Dashboard composition.** One ledger card, four equal columns, one bare glyph each, `Space.lg` gaps — no dead third. Graph directly on the canvas. Apps card with real `NSWorkspace` icons and a row fill, Hours card with 24 bottom-anchored pixel columns and a readout that becomes the tooltip. Equal height via `fixedSize(horizontal:false, vertical:true)`. `HoldToTalkHint` is gone; the empty state is the example, labelled `Badge("Example")`. All three Pass-3 rules honoured.
- **Onboarding.** Four steps, 640×520 fixed, 480pt column, footer 64, dots centred, field reveal stepped 14×, then collapse → grow → travel with the slot measured **live** through a preference key so exactly one dot exists, Reduce Motion rendering the landed state. `PixelDiscFlightTests` covers grow, arc, monotonic shrink, clamping and the landed frame.
- **Motion.** `Motion` matches Pass 1 §5.2 token for token; `Reveal` staggers 70ms; no `linear`, `easeInOut`, `spring(` or `bouncy` survives lint; route change is an opacity cross-fade.
- **Enforcement.** `tools/lint-forbidden` is not theatre: 400-line files, raw controls in features, `NSCursor`, strokes, `Image(systemName:)` outside `Icon`, hex outside tokens (canvas ramps named as exceptions), weights above Medium, off-table font sizes, `.popover`, `AppSlider`, `isMovableByWindowBackground`, `.hierarchical`, `Menu {`, `.focusable()` without `.focusEffectDisabled()`, icons outside 9/12/14/16. **It passes.** The gaps in the table above are gaps in *coverage*, not in intent.

---

## 5. Not verified by me

Honest boundary of this audit:

- **No screenshots were taken.** Every judgement here is static: source, lint, and arithmetic. The things that need eyes — the disc flight timing, the equal-height lower half at real sizes, the sidebar blur over a real desktop, the light-mode step visibility — are **unverified**. `docs/open-questions.md` says the same thing in its own words.
- **No build or test run in this pass.** The last full run I have evidence for was green (lint + five packages + 77 tests). The graph-clipping arithmetic in §1.3 is derived from the code, not observed on screen — it should be reproduced by resizing the window past ~1076pt before it is trusted.
- I did not audit the Island, the menu-bar extra, or `CommandPalette` beyond the scrim colour; the rebuild documents declare the first two out of scope.
- `safeAreaBar` vs `safeAreaInset`: the code uses `safeAreaInset` and comments that the target is macOS 15. Pass 2 §14 asked the PR to name which shipped; there is no PR, and `DESIGN.md` does not record it. Not a visual defect — `.scrollEdgeEffectStyle(.soft)` is applied under `#available(macOS 26)` — but the paper trail Pass 2 asked for does not exist.

---

## 6. What to fix, in order

Orders of magnitude: items 1–3 are worth ~9 points of alignment; 4–6 another ~5; the rest is polish.

1. **Pick one UI face and enforce it.** Decide the conflict (my call: keep Albert Sans, as `DESIGN.md` §9 and the bundled variable font already say, and because Serif Vinci + Albert Sans is a real pairing while SF Pro + Serif Vinci is not), then replace every `.system(size:)` used for text with a `Typography` role, and add the lint rule that makes `.system(size:` illegal outside `Typography.swift`. This also fixes `SectionHeader`'s 15 Regular → 15 Medium.
2. **Wire `vm.isFnHeld` into `CleanupCard`.** Expose the session-state stream through an L2 protocol on `DashboardViewModel`, exactly as Pass 3 §12.4 specifies.
3. **Rewrite `DESIGN.md`** to the code: shell, search, toolbar, tokens, two text levels, monochrome icons, macOS 15 + gated 26 features, 880×560, and a written entry for each of the ~12 undocumented components. Then delete the stale lines in `docs/open-questions.md`.
4. **Make the graph measure itself.** Compute height and hover from the measured `size.width` (or draw the grid inside a `GeometryReader` that owns both), so the year graph cannot clip and the tooltip cannot lie.
5. **One full stop, one size.** Land the onboarding disc at 5 cells × 1.5pt to match every page title.
6. **Guard the sidebar animation** with `reduceMotion ? nil : Motion.slide`.
7. **Close the lint gaps**: `Divider()`, off-grid spacing literals, `help:` on `SettingRow`, `.system(size:` outside `Typography`. The `Divider()` rule will immediately surface five live hits.
8. **Then the small ones**: `timeSaved = "clock"`, one disabled opacity, a legend swatch on the grid, `contrastStroke` on fields and buttons, `ContentUnavailableView` for errors, the last non-token colour.

---

## 7. One paragraph, in the voice this repo deserves

Swapping the logo on this app changes nothing — it already looks like no other dictation tool, and that is the hardest test in the brief, passed. The dark ladder is disciplined, the accent appears once per view, the eyebrow labels and dotted meta chains and boxed icons are gone, and the pixel full stop is a real identity rather than a sticker. But a design review does not grade intentions, and it does not grade the parts that are clean: it finds the row where the trigger is one typeface and the answer is another, the graph that cuts its own bottom row when the window grows, the dot that flew across the screen at twice the size it will ever be again, and the spec that has been describing a different app for two passes. Fix those six and this is a 93.
