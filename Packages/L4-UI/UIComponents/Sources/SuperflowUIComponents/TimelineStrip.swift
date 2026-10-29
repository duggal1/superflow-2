import SuperflowDesignSystem
import SwiftUI

public struct TimelineStrip<Content: View>: View {
    private let duration: TimeInterval
    @Binding private var hover: TimeInterval?
    private let onJump: (TimeInterval) -> Void
    private let content: (CGFloat, TimeInterval?) -> Content
    @State private var width: CGFloat = 0
    @State private var keyboardTime: TimeInterval = 0

    public init(duration: TimeInterval, hover: Binding<TimeInterval?>,
                onJump: @escaping (TimeInterval) -> Void,
                @ViewBuilder content: @escaping (CGFloat, TimeInterval?) -> Content) {
        self.duration = max(0, duration)
        _hover = hover; self.onJump = onJump; self.content = content
    }

    public var body: some View {
        content(width, hover)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .contentShape(.rect)
            .gesture(SpatialTapGesture().onEnded { point in
                onJump(min(max(point.location.x / max(width, 1), 0), 1) * duration)
            })
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hover = min(max(point.x / max(width, 1), 0), 1) * duration
                case .ended: hover = nil
                }
            }
            .clickable(duration > 0)
            .focusable().focusEffectDisabled().keyboardFocusRing(radius: Radius.field)
            .onKeyPress(.leftArrow) { move(-10); return .handled }
            .onKeyPress(.rightArrow) { move(10); return .handled }
            .onKeyPress(.return) { onJump(keyboardTime); return .handled }
            .accessibilityElement()
            .accessibilityLabel("Meeting timeline")
            .accessibilityValue(Humanize.duration(hover ?? keyboardTime))
            .accessibilityAdjustableAction { move($0 == .increment ? 10 : -10) }
            .accessibilityAction { onJump(keyboardTime) }
    }

    private func move(_ delta: TimeInterval) {
        keyboardTime = min(max(keyboardTime + delta, 0), duration)
        hover = keyboardTime
        onJump(keyboardTime)
    }
}
