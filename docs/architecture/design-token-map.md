# Design token map

`DESIGN.md` is the source of truth. The app shell consumes these existing tokens rather than defining app-only colors, spacing, or radii. `PLAN.md` §18 adds product rules (Hugeicons, pointer cursor, focus rings) that sit on top of the visual tokens.

## Foundations

| Token group | Source | Design specification | App use |
|---|---|---|---|
| Surface, text, accent, badge and dot colors | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Colors.swift` | `DESIGN.md` §3 | Main window, sidebar, feature surfaces, badges, status dots. Blue 600 is the only accent; `#0A0A0A` / `#141414` remain the dark surfaces. |
| Spacing, radii, control heights, window and sidebar sizes | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Layout.swift` | `DESIGN.md` §6 | 4pt grid (`Space.grid`), 24pt content padding, card/nested/field radii, 28pt rows, 960×640 window minimum, 220–320pt sidebar. |
| Type roles and display fallback | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Typography.swift` | `DESIGN.md` §5 | SF Pro Regular/Medium for UI; Exposure Italic only at ≥28pt display sizes, with a serif-italic fallback and zero tracking when the font is absent. |
| Motion durations and reduce-motion behavior | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Motion.swift` | `DESIGN.md` §9 | Shared transitions; every animated component branches on `accessibilityReduceMotion`. |
| Appearance | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/ThemeStore.swift` | `DESIGN.md` §§3, 11 | Persisted light/dark theme shared by the Island and main window. |
| Glass and material fallback | `Packages/L4-UI/UIComponents/Sources/SuperflowUIComponents/Glass.swift` | `DESIGN.md` §§2, 7 | `GlassSurface` / `GlassGroup` / `FloatingPanel` for the Island, command palette and toasts only. Content surfaces use `Tok.card`, never glass or shadows. |

## Interaction primitives

| Component | Source | Tokens / rules |
|---|---|---|
| Pointer cursor | `UIComponents/PointerCursor.swift` | The single `pointerCursor(enabled:)` modifier owns `NSCursor` push/pop. Every interactive control applies it; feature packages must not call `NSCursor` directly. |
| Focus ring | `UIComponents/PointerCursor.swift` | `focusRing(_:radius:)` uses `Tok.accent`, `Radius.focusRing` (2pt) and `Radius.focusOffset` (2pt). |
| Buttons | `UIComponents/Buttons.swift` | `PrimaryButton` / `SecondaryButton` / `IconButton` / `TextButton` / `ClickableSurface`; heights from `ControlHeight`, 4pt-multiple padding, `Tok.accent` only on primary. |
| Inputs | `UIComponents/Inputs.swift` | `SearchField`, `LabeledField`, `LabeledTextEditor`, `SegmentedControl`, `ToggleRow`, `SwitchControl`, `OptionRow`, `SliderRow`, `StepperRow`, `SelectRow`; `Radius.field`, `Tok.field` / `Tok.button`, `Tok.text2` for readable secondary text. |
| Navigation | `UIComponents/Navigation.swift` | `SidebarItem` (28pt row, `Tok.selection` selected state), `SidebarSectionLabel` (`Tok.text2`), `ToolbarIconButton`. |
| Indicators | `UIComponents/Indicators.swift` | `BadgeView` (`BadgeVariant.at` wraps negative indexes), `DotView`, `BadgeRow`, `KeyCap` (`Radius.chip`, 24pt minimum). |
| Progress and notices | `UIComponents/Controls.swift` | `ProgressBar`, `NoticeBanner`; reduce-motion aware. |
| Toasts | `UIComponents/Toast.swift` | `ToastQueue` (bounded) + `ToastCenter` + `ToastHost`; glass surface, `DotTone` per style, action/undo closures released on dismissal, reduce-motion transition. |

## Content components

| Component | Source | Tokens / rules |
|---|---|---|
| Card and section header | `UIComponents/Surfaces.swift` | `Tok.card`, 1pt `Tok.border`, `Radius.card`; no content shadows or gradients. |
| Stat tile | `UIComponents/Surfaces.swift` | `StatTile`; value uses `Typography.title` (22pt), label/detail `Typography.secondary` + `Tok.text2`, numeric transition disabled under reduce motion. |
| Empty state | `UIComponents/Surfaces.swift` | `EmptyState`; 28pt Hugeicon in `Tok.text3`, headline title, body message capped at 360pt. |
| Contribution graph | `UIComponents/ContributionGrid.swift` | `ContributionGrid` / `ContributionLayout`; 53×7 Sunday-first cells from `StatsEngine.contributions`, 5 levels (`levelCount`), 12pt cells with 4pt gaps, `Tok.accent` alpha ramp, `Tok.border` for empty cells, future days at 0.35 opacity, O(n) chunking. |
| Command palette | `UIComponents/CommandPalette.swift` | `CommandPalette` + `CommandPaletteModel`; ⌘K surface, `FloatingPanel`, 560pt width, 44pt search row, `Tok.selection` for the highlighted row, arrow/return/escape handling, wrap-around selection, query reset on close, reduce-motion scale. |
| Waveform | `UIComponents/Waveform.swift` | `WaveformView`; bar levels throttled by the Island model to ≤30fps. |
| Pixel field | `UIComponents/PixelField.swift` | `PixelField` + `PixelRenderer`; onboarding hero only, `PixelPalette.blue`, deterministic seed, reduce-motion static frame. |

## Island geometry

| Token | Source | Value / rule |
|---|---|---|
| Compact / expanded widths | `FeatureIsland/IslandMetrics.swift` | 280pt / 460pt; must match the AppKit panel. |
| Compact / expanded heights | `FeatureIsland/IslandMetrics.swift` | 60pt / 160pt. |
| Top inset | `FeatureIsland/IslandMetrics.swift` | `Layout.islandTopInset` (6pt). |
| Drag threshold | `FeatureIsland/IslandDragPolicy.swift` | `Layout.islandDragThreshold` (4pt) radial distance; below is a click, at/above is a drag. |

## Accessibility and appearance checks

- Every interactive control exposes an accessibility label and applies the shared pointer cursor; list rows add selection traits.
- Feature views support light and dark schemes through `Tok` and `@Environment(\.colorScheme)`; badges and dots resolve their own light/dark ramps.
- Reduce Motion disables scale/move/numeric transitions; Reduce Transparency is honored by the glass fallback.
- Keyboard reachability: History supports up/down selection, the command palette supports arrows/return/escape, and focus rings use the shared token.
