import SuperflowDesignSystem
import SwiftUI

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
