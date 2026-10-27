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
| Type | six roles | add **Metric**: SF Pro 28 Medium, tabular. Nothing else is added |
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
    // Sidebar. Concepts match the current screens; the artwork is Apple's.
    case dashboard = "square.grid.2x2", history = "clock.arrow.circlepath", dictionary = "character.book.closed"
    case shortcuts = "command", meetings = "person.2.wave.2", settings = "gearshape"
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
| 2 | Three permissions. | Four rows: Microphone, Accessibility, Input Monitoring, and the Globe key (detected, with "Open Keyboard settings" when it needs to be Do Nothing). Each row: title, one-line reason, trailing control: accent `Grant` (the one filled button on screen), quiet `Open Settings` (text only, no icon), or `Granted` with a `checkmark`. Rows re-check on `didBecomeActive`. No Recheck button, no "0 of 3" counter. | Continue (enabled when the three required are granted, `Set up later` otherwise) |
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