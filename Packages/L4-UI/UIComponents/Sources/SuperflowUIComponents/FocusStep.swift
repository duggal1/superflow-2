import SuperflowDesignSystem
import SwiftUI

/// Our ring is the only focus indicator in the app: 2 pt accent, offset 2, drawn
/// for keyboard navigation only (§3 of pass 3). It lives in this file because
/// strokes are allowed only in the focus-ring file and `Surfaces.swift`.
public struct FocusRing: View {
    public let radius: CGFloat
    public let active: Bool

    public init(radius: CGFloat, active: Bool) {
        self.radius = radius
        self.active = active
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Tok.accent, lineWidth: 2)
            .padding(-4)
            .opacity(active ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: active)
            .allowsHitTesting(false)
    }
}

/// Applied INSIDE the focusable view (its label, or a `ButtonStyle` body), never
/// on the view itself: `isFocused` in the environment reflects the nearest
/// focusable ancestor, so applying this on the focusable view reads the wrong
/// scope and the ring never lights.
@MainActor
private struct KeyboardFocusRing: ViewModifier {
    let radius: CGFloat
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content.overlay {
            FocusRing(radius: radius, active: focused && InputModality.shared.isKeyboard)
        }
    }
}

public extension View {
    func keyboardFocusRing(radius: CGFloat) -> some View {
        modifier(KeyboardFocusRing(radius: radius))
    }
}

/// Pass 2's keyboard indicator: one `wash` fill step in the control's own shape.
/// Pass 3 replaces it with `FocusRing` on every control it lists (segmented,
/// toggle, buttons, dropdown, slider); this stays until the last caller moves.
public extension View {
    func focusStep<S: Shape>(_ shape: S = Capsule()) -> some View {
        modifier(FocusStep(shape: AnyShape(shape)))
    }
}

private struct FocusStep: ViewModifier {
    let shape: AnyShape
    @Environment(\.isFocused) private var focused
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay { if focused { shape.fill(Tok.wash) } }
            .overlay { if focused && contrast == .increased { shape.stroke(Color.primary, lineWidth: 2) } }
            .animation(.easeOut(duration: 0.10), value: focused)
    }
}
