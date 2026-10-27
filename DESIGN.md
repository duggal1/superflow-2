# DESIGN.md — Dark Funnel for macOS

**Audience:** coding agents building the app.
**Status:** the spec. If code and this document disagree, the code wins — then fix this document in the same change.

Numbers are the spec. When a task says "more X", "sharper", or "smoother", tune the numbers. Do not replace the system, and do not add effects.

---

## 1. Protocol (every UI task)

1. **Declare tokens first.** Before writing a view, list the surface steps, spacing, radii, type roles, control heights and SF Symbols it will use. Use only those.
2. **Native before custom.** Walk the ladder in §5.1. Stop at the first rung that works.
3. **Build with token names.** No literals for color, spacing or radius outside `Tokens/`.
4. **Run the mechanical checks** (§18). Every command returns zero hits, except the named exceptions.
5. **Screenshot and review** (§19): light, dark, Increase Contrast, Reduce Transparency, Reduce Motion, minimum window size, collapsed sidebar. Fix before reporting done.
6. **Delete** anything that carries no information and no affordance.

If an API in this document does not compile against your SDK, check the Xcode documentation for the current name. Do not fall back to a custom or faked version.

---

## 2. Rules

1. **Paper, ink, one accent.** Blue 600 `#2563EB` is the only brand color. Status hues exist only inside badges and dots.
2. **No borders.** Surfaces separate by color step, never by stroke. The only strokes in the app are the **focus ring** and the **selected state** (§6.4). No `Divider()`, no hairlines, no outlined cards, no outlined buttons. One accessibility exception: Increase Contrast (§15).
3. **Two layers.** Navigation floats on Liquid Glass. Content is solid. Never swap them.
4. **Glass and blur are system-made.** `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, system materials. Never fake them with gradients, strokes, opacity stacks or hand-rolled blur.
5. **Native first.** Native components, native behavior, native menus, native shortcuts. Custom only where this document specifies it.
6. **Icons are SF Symbols.** Only. No Lucide, Heroicons, Font Awesome, emoji, PNG or custom SVG icons. (§7)
7. **Dark mode is first-class.** Background `#0A0A0A`. Check every view in both modes.
8. **No glow, no gradients, no shadows on content.** Depth comes from surface steps. Nothing else.
9. **Every pixel is justified.** Tokens only. Whole points. Optical alignment checked by eye. A 1pt misalignment is a bug.
10. **Motion explains, never decorates.** Reduce Motion renders the final state, not a blank one.
11. **Text is real text.** Selectable, VoiceOver-readable. Pixel art never sits behind it.
12. **The slop test.** Swap the logo. If the screen could belong to any other SaaS, redo it. (§3)

---

## 3. Anti-slop

Slop is the default output of a model that has seen ten thousand dashboards. This app does not look like them.

### 3.1 Banned

- Gradient text, gradient fills, purple-to-blue "AI" gradients, glows, neon shadows, mesh backgrounds
- `sparkles`, `wand.and.stars` or any glyph used to mean "AI". The product is not a sparkle.
- Emoji as icons. "✨ New" pill badges. Centered pill-above-headline patterns.
- A row of four KPI cards above a line chart above a table. Lead with the work surface (§12).
- Icon-in-a-tinted-rounded-square card grids. Three feature cards in a row.
- Outlined cards, outlined buttons, divider lines between rows
- Shadows on content. Fake depth. Hand-drawn "glass" built from blur + stroke + opacity.
- Lorem ipsum, "Acme Inc", "John Doe", round fake numbers, fake testimonials. Use realistic data: real-looking company names, titles, domains, reply rates like `31.4%`.
- Bouncy springs, looping shimmer skeletons, confetti, decorative animation
- Marketing voice inside the product: "Supercharge your outreach!", "Oops!", "Let's get started!"
- Unmodified system defaults where this spec sets a value, and spec values replaced by guesses

### 3.2 What good looks like

- **Restraint.** Fewer elements, each placed on purpose. If removing something changes nothing, remove it.
- **Hierarchy through space and surface**, then size, then color. In that order.
- **One moment of character per screen**, at most. The pixel Canvas (§13) or the Exposure display type (§9). Not both stacked, never in dense UI.
- **Density that reads as calm.** B2B users scan. Tight rows, aligned numbers, clear grouping.

### 3.3 Reference: progress is quiet

Progress for steps is three small capsules, not a glowing fill bar. The active capsule widens; past and future capsules are different surface steps. The Swift version is in §17.6.

---

## 4. Platform

| Item | Value |
|---|---|
| Language / UI | Swift, SwiftUI first; AppKit only for gaps |
| Target | macOS 26+ (Liquid Glass). If you must support older, gate with `#available(macOS 26, *)` and fall back to `.regularMaterial` |
| Shell | `NavigationSplitView`: glass sidebar + solid content |
| Icons | SF Symbols only, hierarchical rendering (§7) |
| Fonts | SF Pro (system) + Exposure Italic (bundled, display only) |
| App icon | Built in Icon Composer as layered artwork. No baked-in shadows or gloss |
| Tint | `AccentColor` asset set to `#2563EB`, and `.tint(Tok.accent)` at the root, so every native control inherits the accent |
| Dependencies | No UI libraries. No icon libraries. No animation libraries |

---

## 5. Native first

Apple's components already solve focus, keyboard, VoiceOver, Increase Contrast, Reduce Transparency, window states and future OS changes. A custom replacement loses all of that and looks like slop. Use native, and style it only through tokens and the modifiers listed here.

### 5.1 Decision ladder

1. **Native component, unstyled.** Use it as-is.
2. **Native component + tokens.** Tint, `controlSize`, `buttonBorderShape`, `scrollContentBackground(.hidden)` + a token background.
3. **Composition of native primitives.** `Label`, `LabeledContent`, `HStack`, `Menu`, `ControlGroup`.
4. **Custom.** Only if this document specifies it (Badge, Dot, ProgressDots, Canvas, Solid button, Card). Anything else needs a written spec added here first.

### 5.2 Component map

| Need | Use | Notes |
|---|---|---|
| App shell | `NavigationSplitView` | glass sidebar + solid detail. Do not restyle the sidebar |
| Sidebar | `List` + `.listStyle(.sidebar)` | system selection and glass |
| Toolbar | `.toolbar`, `ToolbarItem`, `ToolbarSpacer` | system glass. Group related actions, separate groups with `ToolbarSpacer` |
| Search | `.searchable` | in the toolbar. No custom search field |
| Data table | `Table` | sortable columns, native selection, `.tableStyle(.inset)`. No row dividers, no custom grid lines |
| Lists | `List` | row height 28, hover/selection from system |
| Detail panel | `.inspector` | for record detail beside a table |
| Forms | `Form` + `LabeledContent` | `.formStyle(.columns)` for settings-like layouts |
| Toggle | `Toggle` `.toggleStyle(.switch)` | |
| Choice | `Picker` | `.segmented` for ≤ 4 options, `.menu` otherwise |
| Menus | `Menu`, `.contextMenu` | every row has a context menu |
| Overlays | `.popover`, `.sheet`, `.confirmationDialog`, `.alert` | system glass and materials |
| Progress | `ProgressView` | linear or circular. Step progress uses ProgressDots (§17.6) |
| Empty / no results | `ContentUnavailableView` | Canvas + Exposure only for onboarding and first-run (§13) |
| Loading placeholder | `.redacted(reason: .placeholder)` | static. No shimmer |
| Tooltips | `.help("…")` | icon-only controls always have one |
| Commands | `.commands`, `.keyboardShortcut` | every action is in the menu bar |
| Settings | `Settings` scene | ⌘, |
| Background app | `MenuBarExtra("Dark Funnel", systemImage: …)` | SF Symbol, never a custom image |
| Text + icon | `Label("Prospects", systemImage: "person.2")` | system alignment and spacing. Never hand-built `HStack(Image, Text)` where `Label` works |

### 5.3 Native controls, styled with tokens

- Primary button in content: `Button` with `SolidButtonStyle(prominent: true)` (§17.3). In a glass layer: `.buttonStyle(.glassProminent)` + `.tint(Tok.accent)`.
- Secondary button in content: `SolidButtonStyle()`. In a glass layer: `.buttonStyle(.glass)`.
- Capsule everywhere: `.buttonBorderShape(.capsule)` on system buttons.
- Control sizes through `.controlSize(.small / .regular / .large)`, never fixed frames, unless the spec in §10 says otherwise.
- Scrolling content under the toolbar: `.scrollEdgeEffectStyle(.soft, for: .top)` and `.backgroundExtensionEffect()` on full-bleed hero content, so glass reads as a layer over content instead of a bar.

### 5.4 Never

- A hand-built switch, checkbox, segmented control, tab bar, dropdown, tooltip, alert, toast chrome or search field when a native one exists
- A custom window chrome, title bar or traffic lights
- A custom scrollbar. A custom context menu. A custom text-selection color.
- Restyling system glass (§11)

---

## 6. Color and surfaces

Plain hex. Tokens resolve per appearance. Surfaces are **solid values**. Never build a surface from opacity over unknown content; alpha shifts with whatever is underneath.

### 6.1 Surface ladder (the replacement for borders)

Each step is one notch lighter in dark, one notch darker in light. A thing stands out because it sits one step above what is behind it.

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#FFFFFF` | `#0A0A0A` | window content |
| `card` | `#F8F8F8` | `#141414` | cards, panels, table container |
| `raised` | `#F1F1F1` | `#1C1C1C` | fields, nested panels, neutral buttons, code chips |
| `hover` | `#E9E9E9` | `#242424` | hover on `raised` things, neutral badge fill |
| `pressed` | `#E0E0E0` | `#2B2B2B` | pressed |

Light `card` is `neutral-100 @ 70%` (or `neutral-50`) composited on white, frozen to `#F8F8F8`. The light-mode step is deliberately soft. If a surface does not read on a real display, **increase the step in the table**. Never add a border, shadow or stroke.

**Layering rules**

- A surface sits on the step below it. `card` on `bg`. `raised` on `card`. Never `card` on `card`.
- Never nest a card inside a card. Nested content uses `raised`.
- Never skip more than one step without a reason.
- Gaps do the rest of the separation (§10). Between rows, space and hover fill replace dividers.

### 6.2 Text

| Token | Light | Dark |
|---|---|---|
| `text` | `#0A0A0A` | `#FAFAFA` |
| `text.2` | `#6B6B6B` | `#A3A3A3` |
| `text.3` (decorative only) | `#A3A3A3` | `#737373` |

Light `text.2` is `#6B6B6B`, darker than the old `#737373`, because it now sits on tinted surfaces and must hold 4.5:1 on `card` and `raised`. Hierarchy uses these three tokens. Never fake it with `.opacity`.

### 6.3 Accent — blue 600

| Token | Light | Dark |
|---|---|---|
| `accent` (fills, primary button, ring) | `#2563EB` | `#2563EB` |
| `accent.hover` / pressed | `#1D4ED8` | `#3B82F6` |
| `accent.text` (links, inline) | `#2563EB` | `#60A5FA` |
| `accent.soft` (selected fill) | `#DBEAFE` | `#2563EB2B` |
| `on.accent` | `#FFFFFF` | `#FFFFFF` |
| `selection` (text selection) | `#BFDBFE` | `#2563EB66` |

Primary action = `accent` fill, white label. One accent-filled element per view. Everything else is a neutral button (`raised`). Dark-mode accent *text* uses `#60A5FA` (`#2563EB` is ≈ 3.8:1 on `#0A0A0A`; fills are fine).

### 6.4 The only two strokes

| State | Spec |
|---|---|
| **Focus ring** | 2pt `accent`, 2pt gap outside the control, radius = control radius + 4. Custom controls only; system controls keep the system ring |
| **Selected** | `accent.soft` fill + 1pt `accent` inner stroke. For selectable cards, segments and custom list items. Native `List` and `Table` selection stays native |

Nothing else may draw a stroke, border or outline. `strokeBorder`, `.stroke`, `.border(` and `Divider()` appear only in the focus-ring and selected modifiers (§17.2), enforced by §18.

---

## 7. Icons — SF Symbols only

Apple's icons are drawn to match SF Pro's weights, sizes and baselines, and they inherit Dynamic color, accessibility and OS updates. A third-party icon is always visibly foreign next to system text and controls.

### 7.1 Rules

1. **Every icon is `Image(systemName:)` or `Label(_, systemImage:)`.** Nothing else renders an icon.
2. **No other icon sets.** No Lucide, Heroicons, Feather, Phosphor, Font Awesome, Material, emoji, PNG/SVG icon assets, or icon fonts. If one appears in code, replace it.
3. **Find the symbol in the SF Symbols app.** Check it exists on the minimum OS, and gate with `#available` if not. If nothing fits: look for a close variant, then compose with symbol badges/overlays, and only then draw a **custom symbol** from the SF Symbols template, matching weight, with the same three-weight/three-scale structure. Never swap in a third-party icon.
4. **Rendering:** `.symbolRenderingMode(.hierarchical)`. `.monochrome` where a flat glyph is needed. Never gradient symbol rendering. Never multicolor except status glyphs that already carry system color.
5. **Weight matches the adjacent text weight** (Regular next to Regular, Medium next to Medium). Do not set a symbol heavier than its label.
6. **Size by font, not by frame.** `.font(.system(size: 13))` or `.imageScale(.medium)`. Never `.resizable()` and scale a symbol.
7. **Color:** `text.2` by default, `text` when active, `accent` only for the primary or selected thing. Status glyphs use badge/dot colors.
8. **Variants:** outline by default, `.fill` for selected/active (`.symbolVariant(.fill)`). Sidebar items let the system choose.
9. **Alignment:** use `Label`. In custom rows, give the symbol a fixed `16×16` frame so columns of icons align, and align text on the first baseline. Never nudge with `.offset`.
10. **Icon-only controls** need `.help("…")` and an accessibility label.
11. **Motion:** state changes use `.contentTransition(.symbolEffect(.replace))`. Allowed effects: `bounce` (confirmation), `pulse` (in-progress), `variableColor` (long-running), `drawOn` for one-time onboarding and completion moments. Never looping decoration.
12. **Never** use `sparkles` / `wand.and.stars` to signal AI, and never put a symbol inside a tinted rounded-square tile as decoration.

### 7.2 Sizes

| Context | Font size | Frame |
|---|---|---|
| Table / list row, badge | 12 | 16×16 |
| Body, buttons, toolbar | 13 | 16×16 |
| Headline rows | 15 | 20×20 |
| Empty state / onboarding | 28 | none |

### 7.3 Allowed non-SF images

Only these: the app mark, brand marks of third parties the product integrates with (official asset, original colors, never redrawn or recolored), user avatars/photos, and Canvas output. Everything else is a symbol.

---

## 8. Badges and dots

Hex values are the Tailwind v3 palette. Badges are used everywhere a status, tag or label appears.

### 8.1 Badge

Flat. **No strokes, no inset shade, no gradient.** Color alone carries it.

- Light: `bg = c100`, `text = c700`
- Dark: `bg = c600 @ 17%`, `text = c200`
- Neutral: `bg = hover` (both modes, so it reads on `bg`, `card` and `raised`); text `#404040` light / `#F5F5F5` dark

Light text uses `c700`, not `c600`: `c600` on `c100` is about 3:1 for yellow, orange and green. `c700` holds ~4.5:1.

| Variant | c100 | c200 | c600 | c700 |
|---|---|---|---|---|
| yellow | `#FEF9C3` | `#FEF08A` | `#CA8A04` | `#A16207` |
| sky | `#E0F2FE` | `#BAE6FD` | `#0284C7` | `#0369A1` |
| blue | `#DBEAFE` | `#BFDBFE` | `#2563EB` | `#1D4ED8` |
| violet | `#EDE9FE` | `#DDD6FE` | `#7C3AED` | `#6D28D9` |
| purple | `#F3E8FF` | `#E9D5FF` | `#9333EA` | `#7E22CE` |
| fuchsia | `#FAE8FF` | `#F5D0FE` | `#C026D3` | `#A21CAF` |
| rose | `#FFE4E6` | `#FECDD3` | `#E11D48` | `#BE123C` |
| orange | `#FFEDD5` | `#FED7AA` | `#EA580C` | `#C2410C` |
| green | `#DCFCE7` | `#BBF7D0` | `#16A34A` | `#15803D` |

**Sizes** (all radius `8`, weight Regular, `lineLimit(1)` unless `wrap`):

| Size | Font | Padding (H / V) | Line height | Height |
|---|---|---|---|---|
| `lg` | 13 | 8 / 2 | 20 | 24 |
| `md` (default) | 12 | 6 / 2 | 16 | 20 |
| `sm` | 10 | 6 / 1 | 16 | 18 |

A badge may carry one leading SF Symbol at the badge's font size. Never an emoji.

**Cycle** (auto-assign): `blue, green, orange, violet, yellow, purple, sky, fuchsia, rose`.

### 8.2 Dot

6pt circle, fill = `c600`.

| Tone | Hex |
|---|---|
| blue | `#2563EB` |
| green | `#16A34A` |
| orange | `#EA580C` |
| purple | `#9333EA` |
| neutral | `#525252` |
| rose | `#E11D48` |

**Cycle:** `blue, green, orange, purple`. Decorative: `accessibilityHidden(true)`. Status must also be stated in text; a dot never carries meaning alone.

---

## 9. Type

SF Pro for everything. Exposure Italic for display moments only (onboarding, first-run empty states, large headings).

| Role | Font | Size | Weight | Notes |
|---|---|---|---|---|
| Display | Exposure Italic | 40 | 500 | line ×0.96, tracking −2 |
| Display S | Exposure Italic | 28 | 500 | line ×0.98, tracking −1.4 |
| Title | SF Pro | 22 | Medium | — |
| Headline | SF Pro | 15 | Medium | — |
| Body | SF Pro | 13 | Regular | macOS default |
| Secondary | SF Pro | 12 | Regular | `text.2` |
| Mono | SF Mono | 12 | Regular | emails, IDs, code |

Laws:

1. **Weights: Regular and Medium only.** Never Semibold or Bold.
2. **Exposure is italic only**, never upright, never bolder than 500, never below 28pt.
3. **Tracking only on Exposure.** SF Pro keeps its native optical tracking.
4. **Prose measure ≤ 720pt.** Headlines `balance`, paragraphs `pretty`.
5. **Every number that can change or sit in a column uses `.monospacedDigit()`.** Numbers in tables are trailing-aligned, with units.
6. **Sentence case** everywhere. No Title Case buttons, no ALL CAPS.
7. **Use text styles or the sizes above.** No other point sizes.

---

## 10. Space, size, radius, pixel precision

**Grid: 4pt.** Steps: `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64`. Anything else (`7`, `13`, `15`) is a bug.

| Item | Value |
|---|---|
| Window min | 960 × 640 |
| Sidebar | 240 (min 220, max 320) |
| Content padding | 24 |
| Card padding | 16 (dense) / 20 (default) |
| Section gap | 32 |
| Gap between cards | 12 (dense) / 16 |
| Row height | 28 (single line) / 40 (two lines) |

**Space does the work of borders.** Inside a group: 4–8. Between groups: 16–32. The gap between groups is always at least double the gap inside them (proximity). Hierarchy comes from this before size or color.

**Control heights:** `24` small · `28` regular · `32` large · `40` onboarding CTA only. Controls in one row share one height.

**Radius**

| Element | Radius |
|---|---|
| Buttons, toggles | Capsule |
| Cards | 16 |
| Nested panels | 12 |
| Fields | 8 |
| Badges | 8 |
| Code chips | 6 |

Radii are **concentric**: inner radius = outer radius − padding. Use `ConcentricRectangle` / `containerShape` where available. Never mix two radii in one control. Use `style: .continuous` on every rounded rectangle.

**Card** = `card` fill, no border, no shadow. **Field** = `raised` fill, no border; focus shows the ring. **Button** = capsule, fill per §17.3, no border, `0.98` scale on press.

### Pixel precision

- Whole points only. No fractional padding, offsets or frames. Canvas snaps to backing pixels (§13.1).
- Equal visual padding on all sides of a container. Check by eye at 2×, not just in code.
- Icons sit on a 16×16 or 20×20 box, centered on the text's x-height, not the line box (§7.1).
- One radius per control. Nested radii concentric.
- Columns align: icons in one column share one frame width; numbers share one trailing edge.
- Take a screenshot at 2×, zoom in, check edges. Misaligned by 1pt = bug. Fix it.

---

## 11. Liquid Glass and blur

Glass is the structural material of the app, not decoration. It lives on the **navigation layer** and floats above solid content. The contrast between the two layers *is* the design. Use it deliberately and use it everywhere it applies.

### 11.1 The layer model

| Layer | What lives here | Material |
|---|---|---|
| 2 — Floating | command palette, bulk-action bar, toasts, inline action bars, popovers, menus | Liquid Glass |
| 1 — Navigation | sidebar, toolbar, sheets, inspectors | Liquid Glass (system) |
| 0 — Content | cards, tables, lists, forms, badges, in-content buttons, Canvas | solid surfaces (§6.1) |

Content scrolls *under* glass. Glass never sits inside content, and content never imitates glass.

### 11.2 Use glass for

- Sidebar and toolbar (automatic with `NavigationSplitView` and `.toolbar`; do not restyle)
- Popovers, menus, sheets, inspectors
- **Command palette (⌘K):** centered floating glass panel
- **Bulk-action bar:** when rows are selected in a table, a glass capsule floats at the bottom of the content with the count and actions
- **Toasts:** glass capsule, bottom center, auto-dismiss, VoiceOver announced
- Inline floating action groups, segmented/tab controls that float above content

### 11.3 Never

- Cards, tables, lists, forms, badges, in-content buttons (solid tokens from §6)
- Glass on glass. Group neighbors in one `GlassEffectContainer`
- Glass behind long-form text
- Canvas art (§13) under glass
- A stroke, shadow or tint added to glass. System glass brings its own edge.

### 11.4 API

```swift
GlassEffectContainer(spacing: 8) {
    HStack(spacing: 8) { /* floating actions */ }
}
.glassEffect(.regular, in: .capsule)
```

- `.glassEffect(.regular.interactive())` for tappable floating controls. `.tint(Tok.accent)` only on the single primary floating action.
- `.clear` glass only over rich media with its own dimming layer. Never over text-heavy content.
- Buttons in a glass layer: `.buttonStyle(.glass)` (secondary), `.buttonStyle(.glassProminent)` + `.tint(Tok.accent)` (primary).
- Morph related glass elements with `glassEffectID(_:in:)` + `withAnimation(.smooth)`.
- Scroll edges: `.scrollEdgeEffectStyle(.soft, for: .top)` so content dissolves into the toolbar.
- Full-bleed content that should extend under the sidebar: `.backgroundExtensionEffect()`.
- Toolbar items stay system glass. In-content buttons stay solid.

### 11.5 Native blur

Blur is the fallback, not a style. Use it only where glass can't go: macOS below 26, window-level translucency, and surfaces AppKit owns.

| Surface | `NSVisualEffectView` material | SwiftUI |
|---|---|---|
| Sidebar (below macOS 26) | `.sidebar`, `.behindWindow` | `.regularMaterial` |
| Popover / menu | `.popover` / `.menu` | `.regularMaterial` |
| Sheet / inspector | `.sheet` | `.thickMaterial` |
| HUD / toast (below macOS 26) | `.hudWindow` | `.ultraThinMaterial` |
| Header over scrolling content | `.headerView` | `.bar` |
| Window backdrop | `.underWindowBackground`, `.behindWindow` | — |

- Let the material decide. Never set a custom blur radius, never tint a material.
- Content stays solid. Cards, tables, badges and buttons are never blurred.
- Text on a material uses `text` or `text.2`, never `text.3`.
- Never stack material on glass, or material on material.
- Keep `state = .followsWindowActiveState` so inactive windows dim natively.
- Dark mode: materials adapt on their own. Do not swap them for `#141414`.
- **Reduce Transparency on:** materials fall back to solid `card`. System glass adapts itself.
- `.blur(radius:)` is a transition effect only (≤ 6pt, e.g. a label resolving in). It is never a surface.

---

## 12. Layout and B2B patterns

Dark Funnel is a work tool. The user came to find, qualify and act on people and companies. The UI shows the work first.

### 12.1 Window anatomy

```
Sidebar (glass, 240)  |  Toolbar (glass): title · search · filters · primary action
  Sections            |------------------------------------------------------------
  Smart lists         |  Content (solid bg, padding 24)
  Saved views         |    Work surface: Table in a card, or a list of cards
                      |    Inspector (glass) opens at the trailing edge on selection
                      |    Bulk-action bar (floating glass) when rows are selected
```

### 12.2 Patterns

- **The table is the product.** Prospect, account and activity views are a native `Table`: sortable, resizable, keyboard navigable, with trailing-aligned numbers and status badges.
- **Selection opens detail.** Row selection fills the inspector. Don't navigate away for a quick look.
- **Filters are visible state.** Applied filters appear as removable badges under the toolbar. One click clears them.
- **Bulk actions float.** Select rows → glass capsule with `N selected` and 2–4 actions.
- **Edit in place.** Cells and fields edit inline. Sheets only for multi-step creation.
- **Command palette (⌘K)** reaches every action, view and record.
- **Status is always shown**, as a dot + text or a badge: what is running, what finished, what failed, and how long ago.
- **Time:** relative in lists (`3h ago`), absolute on `.help`.
- **No dashboard-as-landing-page.** The first screen is the last place the user left, or the task queue.

### 12.3 States (every view ships all of them)

| State | Native tool |
|---|---|
| Empty (first run) | Canvas + Display S + one primary action (§13) |
| Empty (no results / cleared filter) | `ContentUnavailableView.search` / `ContentUnavailableView` with a symbol, a title, one action |
| Loading | `ProgressView` for known tasks, `.redacted(reason: .placeholder)` for lists. No shimmer |
| Error | `ContentUnavailableView` with a retry action, plus a plain-language reason |
| Offline / disabled | `.disabled`, with `.help` stating why |

---

## 13. Canvas

The signature: a living blue pixel field that opens a ragged hole around real text, collapses into a single pixel disc, and lands as the full stop. Use it for onboarding, first-run empty states, and long-running progress. Never in dense UI.

### 13.1 Grid

- **Cell:** 16pt (12pt compact, below 640pt wide).
- Every edge snaps to whole cells, then to backing pixels: `round(v * scale) / scale`, `scale = min(backingScale, 2)`.
- No anti-aliasing, no blur, no rounded shader output. Nearest-neighbor if you render to a texture.
- **Metal** (`MTKView` + fragment shader) for animated fields. **SwiftUI `Canvas`** for static or tiny surfaces (≤ 40 × 40 cells).

### 13.2 Palette

Three tones per surface. Never four.

| | deep | mid | pale |
|---|---|---|---|
| Light | `#FFFFFF` | `#93C5FD` | `#2563EB` |
| Dark | `#0A0A0A` | `#1E3A8A` | `#2563EB` |

`deep` is the page background, so holes and cores read as empty.

### 13.3 Tone map

Noise `v` against `G = [0.42, 0.49, 0.55, 0.61]` gives five bands, collapsed to three colors:

| Band | Result |
|---|---|
| 0 | `deep` |
| 1 | even checker cell → `mid`, else `deep` |
| 2 | `mid` |
| 3 | even checker cell → `pale`, else `mid` |
| 4 | `pale` |

Checker unit = `max(1, round(cell × scale / 10))` device pixels. Every in-between value becomes a 2×2 checker of two flat tones. Never interpolate smoothly.

### 13.4 Noise

- Frequency: `h = 2.4 / width`.
- `fbm = 0.6·n(p) + 0.3·n(2p) + 0.1·n(4p)`, value noise with smoothstep interpolation.
- **Block pass:** if `n(1.3·h·p, seed + 7) > 0.6`, sample at the center of a 3-cell block instead. This makes the occasional larger cluster.
- **Cover:** `v −= (cover − 0.5) × 0.25`. Default `0.5`.
- **Drift:** `shift = sin(t · 2π / drift) · width / 6`, rounded to a cell. `drift` = seconds per pass. Default `120`. `0` = static.

### 13.5 Text hole

- Union of the text views' frames (anchor preferences), expanded by `padX = 5`, `padY = 3` cells.
- Inside: tone 0, unconditionally.
- Near it: `v −= 0.9 × clamp(1 − d / falloff)`, `falloff = 3` cells. Cells dissolve through the dither bands instead of cutting off.
- **Shape:** `organic` (ellipse radius `− 1 − edgeNoise`, noise ±0.16 at frequency `cell × 5`) or `rect`. Never a rounded rect, a mask, or a gradient.
- Several text blocks make **one** hole. Separate holes need separate fields.

### 13.6 Collapse

- Ring radius goes from `reach + 10 cells` to `−10 cells`.
- Ragged edge: low-frequency noise ±7 cells + per-cell hash ±1.5 cells.
- Outside the ring: transparent. Within 3 cells inside it: `v −= 0.5 × smoothstep(−3 cells, 0, m)`, so cells lighten as they die.

### 13.7 Disc (the full stop)

- `N` odd cells: `5` hero, `7` compact, `11` default.
- Snap origin and cell size to device pixels **every frame**.
- Inside test: `length(cellCenter − N/2) ≤ radius`.
- Tone: `v = 0.80 − 0.22·t² + (hash − 0.5)·0.12`, `t = r / (N/2)`.
- Speckle: `v −= 0.17` on ~16% of cells, never on the rim (`t < 0.75` guard), so the silhouette stays a clean circle.
- Travel: cell size lerps `homeCell → slotSize / N`; origin lerps home → slot; arc = `sin(π · travel) · height · 0.06`.
- The **slot** is a real SwiftUI view measured live. Resizing or re-padding it changes the dot.

### 13.8 Reveal

Radial from the center, jittered per cell, in whole steps:

```
order   = min(1, |g| / √2) · 0.82 + hash(cell, seed + 3) · 0.18
visible = order <= ceil(easeOutCubic(raw) · steps) / steps
```

`steps = 14`, `revealMs = 1300`. Stepping makes cells switch on instead of fading in.

### 13.9 Driving it

Drive `collapse`, `grow` and `travel` from **one progress value** (onboarding step, task progress), eased per §14. Never from timers. Order: reveal → hole opens around text → collapse → disc grows → disc travels to slot.

Suggested API:

```swift
PixelField(
    clear: [titleFrame, bodyFrame],     // text frames, unioned into one hole
    clearPad: (x: 5, y: 3), clearShape: .organic, falloff: 3,
    collapse: collapse,                 // 0...1
    disc: .init(cells: 5, grow: grow, travel: travel, slot: slotFrame),
    palette: .blue,                     // §13.2
    cell: 16, seed: 11, cover: 0.5, dither: 0.5,
    steps: 14, revealMs: 1300, drift: 120
)
```

### 13.10 Performance

- One render loop per field. Pause when the window is occluded, minimized, or the field is off-screen (`NSWindow.occlusionState`, `onDisappear`).
- 60fps cap. Drift alone needs ≤ 30fps.
- Redraw only when a signature changes: size, shift, hole, collapse, disc.
- Animation values go in as uniforms. Never rebuild the pipeline per frame; never allocate per frame.
- Backing scale capped at 2.

### 13.11 Rules

- Never draw text in the shader. Text is a real view on top.
- Never behind glass, lists, or dense UI.
- Palette stays three colors.
- Decorative: `accessibilityHidden(true)`. Meaningful (the logo): `accessibilityLabel`.
- **Reduce Motion:** `reveal = 1`, `drift = 0`, disc in its final state, no loop.

---

## 14. Motion

| Intent | Curve | Duration |
|---|---|---|
| Hover / press | `.easeOut` | 0.10s |
| UI settle | `.timingCurve(0.23, 1, 0.32, 1)` | 0.18–0.42s |
| Entrance | `.timingCurve(0.22, 1, 0.36, 1)` | 0.78s |
| Small spring | `.snappy` | — |
| Large spring | `.smooth` | — |
| Symbol swap | `.contentTransition(.symbolEffect(.replace))` | system |

- **Stagger 70ms.** Entrances never use `linear` or ease-in-out.
- Animate transform and opacity only. Never animate layout size, except where a component's spec says so (ProgressDots).
- Nothing animates before it is on screen.
- Hover in is fast (0.10s); return is slower.
- No looping or ambient motion outside the Canvas drift.
- **Reduce Motion:** `@Environment(\.accessibilityReduceMotion)` → render the final state, no stagger, no drift, no springs, no symbol effects.

---

## 15. Accessibility and Mac behavior

- **Contrast:** `text.3` is decorative only. Anything a reader must act on uses `text.2` or darker. Body and secondary text ≥ 4.5:1 on their surface. Links in dark use `accent.text`.
- **Borderless means the fill carries the shape.** Fields and buttons always use `raised` or darker so their edge exists in color, and the focus ring shows state.
- **Increase Contrast:** this is the one place a stroke is allowed. Widen the surface steps (card light `#F0F0F0` / dark `#1A1A1A`, raised light `#E6E6E6` / dark `#242424`) and add a 1pt outline at 20% white (dark) / `#D4D4D4` (light) on fields, buttons and cards.
- **Reduce Transparency:** materials fall back to solid `card`.
- **Focus:** per §6.4. Custom controls expose the ring on keyboard focus (`focusable()` + `@FocusState`). System controls keep the system ring.
- **Keyboard:** every action is a menu-bar command with a ⌘ shortcut. ⌘K opens the command palette. Tab order follows visual order.
- **No hover-only behavior.** Hover accelerates; focus and click must reach the same state.
- **VoiceOver:** every icon-only control has a label and `.help`. Badges read their text; dots are hidden; status is always also in text.
- **Windows:** support resize, full screen, sidebar collapse (⌘⌥S), and state restoration.
- **Text:** selectable where users may copy (emails, IDs, names).

---

## 16. Copy

- Sentence case. Verbs for actions: `Add prospects`, `Export list`. Nouns for destinations.
- Plain, specific, short. `3 emails failed to send`, not `Something went wrong`.
- Errors say what happened and what to do. No blame, no apology, no exclamation marks.
- No marketing voice, no filler (`Let's`, `Oops`, `Awesome`, `Supercharge`, `Seamlessly`).
- Empty states: one title, one sentence, one action.
- Numbers carry units and context. `31.4% reply rate`, not `31.4`.
- Use real data in every mock and preview.

---

## 17. Swift skeleton

### 17.1 Tokens

`Tokens/Tokens.swift`. The only file where hex literals are allowed (plus `BadgeTokens.swift`).

```swift
import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

enum Tok {
    // Surface ladder (§6.1)
    static let bg      = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x0A0A0A))
    static let card    = Color(light: Color(hex: 0xF8F8F8), dark: Color(hex: 0x141414))
    static let raised  = Color(light: Color(hex: 0xF1F1F1), dark: Color(hex: 0x1C1C1C))
    static let hover   = Color(light: Color(hex: 0xE9E9E9), dark: Color(hex: 0x242424))
    static let pressed = Color(light: Color(hex: 0xE0E0E0), dark: Color(hex: 0x2B2B2B))

    // Text (§6.2)
    static let text  = Color(light: Color(hex: 0x0A0A0A), dark: Color(hex: 0xFAFAFA))
    static let text2 = Color(light: Color(hex: 0x6B6B6B), dark: Color(hex: 0xA3A3A3))
    static let text3 = Color(light: Color(hex: 0xA3A3A3), dark: Color(hex: 0x737373))

    // Accent (§6.3)
    static let accent      = Color(hex: 0x2563EB)
    static let accentHover = Color(light: Color(hex: 0x1D4ED8), dark: Color(hex: 0x3B82F6))
    static let accentSoft  = Color(light: Color(hex: 0xDBEAFE), dark: Color(hex: 0x2563EB, alpha: 0.17))
    static let accentText  = Color(light: Color(hex: 0x2563EB), dark: Color(hex: 0x60A5FA))
}

enum Sp {
    static let p4:  CGFloat = 4
    static let p8:  CGFloat = 8
    static let p12: CGFloat = 12
    static let p16: CGFloat = 16
    static let p20: CGFloat = 20
    static let p24: CGFloat = 24
    static let p32: CGFloat = 32
    static let p40: CGFloat = 40
    static let p48: CGFloat = 48
    static let p64: CGFloat = 64
}

enum Rad {
    static let code:   CGFloat = 6
    static let field:  CGFloat = 8
    static let badge:  CGFloat = 8
    static let nested: CGFloat = 12
    static let card:   CGFloat = 16
}

enum Ctl {
    static let small:   CGFloat = 24
    static let regular: CGFloat = 28
    static let large:   CGFloat = 32
    static let cta:     CGFloat = 40
}
```

### 17.2 Surfaces, focus ring, selected state

The only code in the app allowed to draw a stroke.

```swift
extension View {
    func card(padding: CGFloat = Sp.p20) -> some View {
        self.padding(padding)
            .background(Tok.card,
                        in: RoundedRectangle(cornerRadius: Rad.card, style: .continuous))
    }

    func raised(radius: CGFloat = Rad.field) -> some View {
        self.background(Tok.raised,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 2pt accent ring, 2pt gap outside, radius + 4. Custom controls only.
    func focusRing(_ on: Bool, radius: CGFloat) -> some View {
        self.overlay {
            if on {
                RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                    .strokeBorder(Tok.accent, lineWidth: 2)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
    }

    /// accent.soft fill + 1pt accent inner stroke.
    func selected(_ on: Bool, radius: CGFloat) -> some View {
        self.background(on ? Tok.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Tok.accent, lineWidth: 1)
                }
            }
    }
}
```

### 17.3 Solid button

Capsule. No border. Steps from the surface ladder.

```swift
struct SolidButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, prominent: prominent)
    }

    private struct Body: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var fill: Color {
            if prominent {
                return configuration.isPressed || hovering ? Tok.accentHover : Tok.accent
            }
            return configuration.isPressed ? Tok.pressed : hovering ? Tok.hover : Tok.raised
        }

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(prominent ? Color.white : Tok.text)
                .padding(.horizontal, Sp.p12)
                .frame(height: Ctl.regular)
                .background(fill, in: Capsule())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
                           value: configuration.isPressed)
        }
    }
}
```

### 17.4 Badge and Dot

```swift
enum BadgeVariant: CaseIterable {
    case neutral, yellow, sky, blue, violet, purple, fuchsia, rose, orange, green

    static let cycle: [BadgeVariant] =
        [.blue, .green, .orange, .violet, .yellow, .purple, .sky, .fuchsia, .rose]
    static func at(_ i: Int) -> BadgeVariant { cycle[i % cycle.count] }

    /// (c100, c200, c600, c700)
    private var ramp: (UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .neutral: return (0xF5F5F5, 0xF5F5F5, 0x525252, 0x404040)
        case .yellow:  return (0xFEF9C3, 0xFEF08A, 0xCA8A04, 0xA16207)
        case .sky:     return (0xE0F2FE, 0xBAE6FD, 0x0284C7, 0x0369A1)
        case .blue:    return (0xDBEAFE, 0xBFDBFE, 0x2563EB, 0x1D4ED8)
        case .violet:  return (0xEDE9FE, 0xDDD6FE, 0x7C3AED, 0x6D28D9)
        case .purple:  return (0xF3E8FF, 0xE9D5FF, 0x9333EA, 0x7E22CE)
        case .fuchsia: return (0xFAE8FF, 0xF5D0FE, 0xC026D3, 0xA21CAF)
        case .rose:    return (0xFFE4E6, 0xFECDD3, 0xE11D48, 0xBE123C)
        case .orange:  return (0xFFEDD5, 0xFED7AA, 0xEA580C, 0xC2410C)
        case .green:   return (0xDCFCE7, 0xBBF7D0, 0x16A34A, 0x15803D)
        }
    }

    func fill(dark: Bool) -> Color {
        if self == .neutral { return Tok.hover }
        return dark ? Color(hex: ramp.2, alpha: 0.17) : Color(hex: ramp.0)
    }
    func text(dark: Bool) -> Color {
        if self == .neutral { return dark ? Color(hex: 0xF5F5F5) : Color(hex: 0x404040) }
        return Color(hex: dark ? ramp.1 : ramp.3)
    }
}

struct Badge: View {
    enum Size {
        case lg, md, sm
        var font: CGFloat   { switch self { case .lg: return 13; case .md: return 12; case .sm: return 10 } }
        var px: CGFloat     { self == .lg ? 8 : 6 }
        var height: CGFloat { switch self { case .lg: return 24; case .md: return 20; case .sm: return 18 } }
    }

    @Environment(\.colorScheme) private var scheme
    var text: String
    var variant: BadgeVariant = .neutral
    var symbol: String? = nil          // optional SF Symbol, never emoji
    var size: Size = .md
    var wrap = false

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size.font, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
            }
            Text(text)
                .font(.system(size: size.font, weight: .regular))
                .lineLimit(wrap ? nil : 1)
        }
        .foregroundStyle(variant.text(dark: dark))
        .fixedSize(horizontal: !wrap, vertical: true)
        .padding(.horizontal, size.px)
        .frame(minHeight: size.height)
        .background(variant.fill(dark: dark),
                    in: RoundedRectangle(cornerRadius: Rad.badge, style: .continuous))
    }
}

enum DotTone: CaseIterable {
    case blue, green, orange, purple, neutral, rose

    static let cycle: [DotTone] = [.blue, .green, .orange, .purple]
    static func at(_ i: Int) -> DotTone { cycle[i % cycle.count] }

    var color: Color {
        switch self {
        case .blue:    return Color(hex: 0x2563EB)
        case .green:   return Color(hex: 0x16A34A)
        case .orange:  return Color(hex: 0xEA580C)
        case .purple:  return Color(hex: 0x9333EA)
        case .neutral: return Color(hex: 0x525252)
        case .rose:    return Color(hex: 0xE11D48)
        }
    }
}

struct Dot: View {
    var tone: DotTone
    var body: some View {
        Circle().fill(tone.color).frame(width: 6, height: 6).accessibilityHidden(true)
    }
}
```

### 17.5 Symbols

Prefer `Label`. Where a bare symbol is needed:

```swift
struct Sym: View {
    var name: String
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    var color: Color = Tok.text2

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size >= 15 ? 20 : 16, height: size >= 15 ? 20 : 16)
    }
}

// Preferred
Label("Prospects", systemImage: "person.2")
Label("Export", systemImage: "square.and.arrow.up")
```

### 17.6 ProgressDots

Step progress. Three capsules on the 4pt grid: inactive `4×4`, active `16×4`, gap `8`. Past and future are different surface steps. The active capsule widens with the entrance curve.

```swift
struct ProgressDots: View {
    var step: Int            // 0-based current step
    var count = 3
    var complete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Sp.p8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(color(for: i))
                    .frame(width: width(for: i), height: 4)
            }
        }
        .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.3),
                   value: step)
        .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.3),
                   value: complete)
        .accessibilityElement()
        .accessibilityLabel("Step \(min(step + 1, count)) of \(count)")
    }

    private func width(for i: Int) -> CGFloat {
        complete ? 12 : (i == step ? 16 : 4)
    }
    private func color(for i: Int) -> Color {
        if complete || i == step { return Tok.text }
        return i < step ? Tok.pressed : Tok.raised
    }
}
```

---

## 18. Mechanical checks

Run from the repo root before reporting any UI task done. Every command returns **zero hits** except the named exceptions. If a hit is legitimate, the spec is wrong, not the code: fix this document in the same change.

```bash
# No strokes, borders or dividers. Allowed only in Surfaces.swift (focusRing, selected)
rg -n 'Divider\(\)|\.border\(|strokeBorder|\.stroke\(' Sources

# No gradients anywhere
rg -n 'LinearGradient|RadialGradient|AngularGradient|MeshGradient|EllipticalGradient' Sources

# No shadows on content
rg -n '\.shadow\(' Sources

# Icons are SF Symbols only. `Image("` allowed only for app mark, brand marks, avatars
rg -n 'Image\("|Image\(uiImage|Image\(nsImage|\.resizable\(\)' Sources
rg -n -i 'lucide|heroicons|feather|phosphor|fontawesome|material-?icons|svgview' .

# Never the AI sparkle
rg -n 'sparkles|wand\.and' Sources

# Weights: Regular and Medium only
rg -n '\.(semibold|bold|heavy|black)\b' Sources

# Hex literals only in Tokens/
rg -n 'Color\(hex|Color\(red|NSColor\(red|#colorLiteral' Sources --glob '!Tokens/**'

# Opacity and blur: review every hit. Allowed: disabled state, SolidButtonStyle, canvas transitions
rg -n '\.opacity\(|\.blur\(' Sources

# Off-grid spacing: any padding / spacing / frame literal not in the §10 steps
rg -n '\.padding\(.*\b(1|2|3|5|6|7|9|10|11|13|14|15|17|18|19)\)' Sources
```

Also verify by hand: no `Table` or `List` draws row separators; no card inside a card; one accent-filled element per view.

---

## 19. Review checklist

**Slop and borders**
- [ ] Slop test passed: swapping the logo makes it a different product
- [ ] Nothing from the §3.1 banned list
- [ ] No borders, dividers, outlines or shadows on content
- [ ] Separation comes from the surface ladder and spacing alone
- [ ] Strokes appear only as focus ring and selected state

**Native**
- [ ] Every control, container and overlay is native or in the §5.1 rung-4 list
- [ ] Every icon is an SF Symbol, hierarchical, weight-matched, in a 16 or 20 box
- [ ] `Label` used for text + icon
- [ ] `ContentUnavailableView`, `ProgressView`, `.searchable`, `.inspector`, `Table` used where they apply

**Glass and blur**
- [ ] Glass only on the navigation and floating layers
- [ ] No glass on glass; neighbors grouped in `GlassEffectContainer`
- [ ] Content solid; no hand-built glass; no tinted or stroked material
- [ ] Reduce Transparency verified

**System**
- [ ] Checked in light, dark, Increase Contrast
- [ ] Background `#0A0A0A` in dark; surfaces from the ladder only
- [ ] Only accent: blue 600; one accent-filled element per view
- [ ] Badges and dots from §8, no ad-hoc colors
- [ ] Weights Regular/Medium only; Exposure italic ≥ 28pt, display only
- [ ] Spacing on the 4pt grid; radii from §10, concentric
- [ ] Numbers monospaced and aligned
- [ ] Every state exists: empty, loading, error, disabled, focus, hover, pressed
- [ ] Reduce Motion handled
- [ ] Every action reachable by keyboard and in the menu bar
- [ ] Canvas: whole cells, three tones, ragged text hole, no AA, one render loop, paused off-screen, never behind text or glass
- [ ] §18 mechanical checks all clean
- [ ] Reviewed a 2× screenshot; no 1pt misalignment

---

## 20. Cheat sheet

```
ACCENT       #2563EB   hover #1D4ED8 (dark #3B82F6)   text-on-dark #60A5FA
LIGHT        bg #FFFFFF · card #F8F8F8 · raised #F1F1F1 · hover #E9E9E9 · pressed #E0E0E0
DARK         bg #0A0A0A · card #141414 · raised #1C1C1C · hover #242424 · pressed #2B2B2B
TEXT         light #0A0A0A / #6B6B6B    dark #FAFAFA / #A3A3A3

BORDERS      none. Color step only. Strokes: focus ring (2pt accent, gap 2) + selected (soft fill + 1pt accent)
ICONS        SF Symbols only · hierarchical · weight = text weight · 16×16 / 20×20 box
NATIVE       NavigationSplitView · Table · List · Form · Menu · .searchable · .inspector
             ContentUnavailableView · ProgressView · Label · .toolbar · .commands

FONTS        SF Pro (UI) · Exposure Italic (display ≥ 28)
WEIGHTS      Regular · Medium
BODY         13   TITLE 22   DISPLAY 40   NUMBERS monospacedDigit

GRID         4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64
PAD          content 24 · card 16/20 · section gap 32 · sidebar 240
RADIUS       capsule buttons · 16 cards · 12 nested · 8 fields/badges · 6 code
CONTROLS     24 · 28 · 32 · 40 (CTA only)

GLASS        sidebar · toolbar · popovers · sheets · ⌘K · bulk bar · toasts
SOLID        cards · tables · forms · badges · in-content buttons
BLUR         system materials only, only where glass can't go
CANVAS       cell 16 · 3 tones · 2×2 checker · hole 5×3 cells · odd-cell disc

HOVER        0.10s   ENTRANCE 0.78s   STAGGER 70ms
REDUCED      final state, no drift, no springs, no symbol effects, solid fallbacks
```