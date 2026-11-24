import SuperflowDesignSystem
import SwiftUI

/// The Island's small in-scene transition. The stage itself crossfades whole
/// scenes against one spring-driven clock; this only handles a mark swapping
/// inside a scene. No blur and no re-layout: a short fade with a tiny rise.
private struct FadeRise: ViewModifier {
    let active: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .scaleEffect(active && !reduceMotion ? 0.98 : 1, anchor: .top)
            .offset(y: active && !reduceMotion ? 3 : 0)
    }
}

public extension AnyTransition {
    static var islandContent: AnyTransition { islandContent(reduceMotion: false) }

    /// Reduce Motion cross-dissolves: no scale, no offset, 0.15 s.
    static func islandContent(reduceMotion: Bool) -> AnyTransition {
        let animation = reduceMotion
            ? Animation.easeOut(duration: 0.15)
            : Motion.islandIn
        let removal = reduceMotion
            ? Animation.easeOut(duration: 0.15)
            : Motion.islandOut
        return .asymmetric(
            insertion: .modifier(active: FadeRise(active: true, reduceMotion: reduceMotion),
                                 identity: FadeRise(active: false, reduceMotion: reduceMotion))
                .animation(animation),
            removal: .opacity.animation(removal)
        )
    }
}
