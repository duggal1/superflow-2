import SuperflowDesignSystem
import SwiftUI

/// The Island's one content transition. Content arrives after the shape has
/// started to open, and leaves before the shape has finished closing.
private struct BlurFade: ViewModifier {
    let active: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active && !reduceMotion ? 6 : 0)
            .opacity(active ? 0 : 1)
            .scaleEffect(active && !reduceMotion ? 0.94 : 1, anchor: .top)
    }
}

public extension AnyTransition {
    static var islandContent: AnyTransition { islandContent(reduceMotion: false) }

    /// Reduce Motion cross-dissolves: no blur, no scale, 0.15 s.
    static func islandContent(reduceMotion: Bool) -> AnyTransition {
        let animation = reduceMotion
            ? Animation.easeOut(duration: 0.15)
            : Motion.islandIn
        let removal = reduceMotion
            ? Animation.easeOut(duration: 0.15)
            : Motion.islandOut
        return .asymmetric(
            insertion: .modifier(active: BlurFade(active: true, reduceMotion: reduceMotion),
                                 identity: BlurFade(active: false, reduceMotion: reduceMotion))
                .animation(animation),
            removal: .opacity.animation(removal)
        )
    }
}
