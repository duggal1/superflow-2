# Design token map

`DESIGN.md` is the source of truth. The app shell consumes these tokens rather than defining app-only colours, spacing or radii.

## Foundations

| Token group | Source | Design specification | App use |
|---|---|---|---|
| Surface, text, accent, button edge, scrim | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Colors.swift` | `DESIGN.md` §4 | Canvas, sidebar washes, cards, fields, buttons, badges, dots. Blue 600 is the only accent. |
| Spacing, radii, control heights, window and sidebar sizes | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Layout.swift` | `DESIGN.md` §4.5, §7 | 4 pt grid, page padding 32, card 20, radii 16/12/8/6, control heights 24/28/32, 960 × 620 default, 880 × 560 minimum, sidebar 220. |
| Type roles | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Typography.swift` | `DESIGN.md` §5 | Albert Sans at 350 (500 for emphasis) for every UI role, SF Pro for the numeric metric; Serif Vinci Italic only at 28 (page/empty titles) and 40 (onboarding). |
| Motion | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/Motion.swift` | `DESIGN.md` §11 | hover 0.10/0.22, settle 0.28, entrance 0.78, slide 0.30, fade 0.18, menu 0.20/0.12, stagger 0.07, snappy/smooth. |
| Appearance | `Packages/L4-UI/DesignSystem/Sources/SuperflowDesignSystem/ThemeStore.swift` | `DESIGN.md` §2 | Persisted light/dark theme shared by the Island and main window. |
| Glass and material fallback | `Packages/L4-UI/UIComponents/Sources/SuperflowUIComponents/Glass.swift` | `DESIGN.md` §3 | `GlassSurface` / `GlassGroup` / `FloatingPanel` for the Island, command palette and toasts only. Content uses `Tok.surface`. |

## Interaction primitives

| Component | Source | Tokens / rules |
|---|---|---|
| Pointer cursor | `UIComponents/Pointer.swift` | The only `clickable(_:)` modifier owns `pointerStyle` and the AppKit cursor rect. Feature packages never call `NSCursor`. |
| Focus ring | `DesignSystem/Surfaces.swift` | `focusRing(radius:active:)` uses `Tok.accent`, 2 pt, 2 pt offset. |
| Buttons | `UIComponents/Buttons.swift` | `AppButtonStyle`, `AppButton`, `SapphireButton`, `IconButton`; 32 pt height, radius 16, SF Pro 14 Medium at −0.35 tracking, `Tok.buttonBorder` 1 pt, inner button blur, `clickable`. |
| Inputs | `UIComponents/Inputs.swift` | `AppField`, `AppTextField`, `PracticeField`, `AppTextEditor`; `Tok.field` / `Tok.well`, radius 8, focus step, `contrastStroke`. |
| Search | `UIComponents/PageChrome.swift` | `SearchField`; capsule, `Tok.field`, caret accent, I-beam, no ring. |
| Navigation | `App/SuperflowApp/Sources/SuperflowAppCore/Windowing/MainWindowRootView.swift` | `MainSidebar` + `SidebarRow`; 220 pt, `NSVisualEffectView(.sidebar, .behindWindow)`, 32 pt rows, `washStrong` pill. |
| Indicators | `UIComponents/Indicators.swift` | `Badge`, `DotView`, `KeyCap`, `Metric`, `ProgressDots`, `NoticeBanner`, `ProgressBar`. |
| Controls | `UIComponents/Controls.swift` | `Segmented`, `AppToggleStyle`, `AppToggle`. |
| Menus | `UIComponents/MenuLayer.swift` | `MenuHost`, `MenuLayer`, `Dropdown`, `ActionMenu`; root overlay, glass panel, no popover. |
| Sliders and steppers | `UIComponents/Sliders.swift` | `TimingSlider` (native `Slider`, 280 + 64 readout), `AppStepper`, `KeyRecorder`. |
| Toasts | `UIComponents/Toast.swift` | `ToastCenter` + `ToastHost`; glass, `DotTone`, reduce-motion transition. |

## Content components

| Component | Source | Tokens / rules |
|---|---|---|
| Card, page chrome, rows | `UIComponents/Surfaces.swift`, `UIComponents/Rows.swift` | `Tok.surface`, radius 16, padding 20, no border; `Page` / `SplitPage` / `PageBar`; `RowButton`, `SettingRow`. |
| Empty state | `UIComponents/EmptyState.swift` | Pixel stop 11 × 4 / 3, display 28 or 15 Medium, one sentence. |
| Contribution graph | `UIComponents/ContributionGrid.swift` | 53 × 7 cells on the canvas, 5-step blue ramp, measured width drives height and hover. |
| Dashboard lower half | `FeatureDashboard/DashboardLowerHalf.swift` | Apps row fill (`accentSoft`), Hours 24 × 8 pixel columns, real `NSWorkspace` icons. |
| Cleanup card | `FeatureDashboard/DashboardCleanup.swift` | LCS word diff, flow layout, hold/release/clean once, `Replay`, `fnHeld` from the physical key. |
| Command palette | `UIComponents/CommandPalette.swift` | `⌘K`, `Tok.scrim`, `FloatingPanel` 560 wide, arrow/return/escape. |
| Waveform | `UIComponents/new-waveform.swift` | `WaveformView` + `WaveformEngine` + `LevelsWaveform`; only waveform drawing path. |
| Mic test | `UIComponents/waveform-mic-test.swift`, `UIComponents/MicLevelSource.swift` | `MicTestView` + `DotMeterEngine`; only mic meter. |
| Pixel identity | `UIComponents/PixelStop.swift`, `PixelField.swift`, `PixelDiscFlight.swift` | 5 × 1.5 full stop, deterministic field, 5-cell disc flight. |

## Island geometry

| Token | Source | Value / rule |
|---|---|---|
| Compact / expanded widths | `FeatureIsland/IslandMetrics.swift` | 280 pt / 460 pt; must match the AppKit panel. |
| Compact / expanded heights | `FeatureIsland/IslandMetrics.swift` | 60 pt / 160 pt. |
| Top inset | `FeatureIsland/IslandMetrics.swift` | `Layout.islandTopInset` (6 pt). |
| Drag threshold | `FeatureIsland/IslandDragPolicy.swift` | `Layout.islandDragThreshold` (4 pt) radial distance. |

## Accessibility and appearance checks

- Every interactive control exposes an accessibility label and applies `clickable`.
- Feature views support light and dark through `Tok` and `@Environment(\.colorScheme)`.
- Reduce Motion removes pill slides, disc flight, waveform motion, reveal offsets and numeric transitions.
- Reduce Transparency falls back to `Tok.surface`; Increase Contrast adds the shared 1 pt stroke.
