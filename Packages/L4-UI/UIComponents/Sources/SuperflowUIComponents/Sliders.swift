import AppKit
import SuperflowDesignSystem
import SwiftUI

public struct AppSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let unit: String
    private static let track: Double = 280
    @State private var physics: ThumbPhysics
    @State private var clock = SliderFrameClock()
    @State private var dragging = false
    @Environment(\.displayScale) private var scale
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 50, unit: String) {
        precondition(range.lowerBound.isFinite && range.upperBound.isFinite && step.isFinite && step > 0)
        _value = value; self.range = range; self.step = step; self.unit = unit
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? min(1, max(0, (value.wrappedValue - range.lowerBound) / span)) : 0
        _physics = State(initialValue: ThumbPhysics(at: fraction * (Self.track - 2)))
    }

    public var body: some View {
        HStack(spacing: 16) {
            TimelineView(.animation(paused: !clock.running)) { timeline in
                let x = physics.step(timeline.date.timeIntervalSinceReferenceDate)
                let _ = physics.settled ? clock.park() : ()
                Canvas { context, size in
                    Self.draw(&context, size, thumb: CGFloat(x), dragging: dragging, scale: scale)
                }
            }
            .frame(width: Self.track, height: 32)
            .keyboardFocusRing(radius: Radius.field)
            .contentShape(.rect)
            .gesture(drag)
            .focusable().focusEffectDisabled()
            .onKeyPress(.leftArrow) { if enabled { nudge(-1) }; return .handled }
            .onKeyPress(.rightArrow) { if enabled { nudge(1) }; return .handled }
            .clickable(enabled)

            Text("\(Int(value).formatted()) \(unit)")
                .appType(.body).monospacedDigit().foregroundStyle(Tok.text2)
                .lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(.numericText(value: value))
                .animation(reduce ? nil : .snappy(duration: 0.15), value: value)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: Self.track + 16 + 64)
        .opacity(enabled ? 1 : Opacity.disabled)
        .onChange(of: value) { _, next in if !dragging { retarget(x(for: next)) } }
        .onChange(of: reduce) { _, on in if on { physics.snap(to: x(for: value)); clock.kick() } }
        .onAppear { physics.snap(to: x(for: value)); clock.kick() }
        .onDisappear { clock.running = false }
        .accessibilityRepresentation { Slider(value: $value, in: range, step: step) }
        .pixelAudit("AppSlider")
    }

    private func x(for value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(1, max(0, (value - range.lowerBound) / span)) * (Self.track - 2) : 0
    }

    private func retarget(_ target: Double) {
        if reduce { physics.snap(to: target) } else { physics.target = target }
        clock.kick()
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard enabled else { return }
                dragging = true
                physics.omega = 64
                let position = min(max(gesture.location.x - 1, 0), Self.track - 2)
                retarget(position)
                let raw = range.lowerBound + position / (Self.track - 2) * (range.upperBound - range.lowerBound)
                let snapped = min(range.upperBound, max(range.lowerBound,
                    range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step))
                if value != snapped {
                    value = snapped
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { _ in
                guard dragging else { return }
                dragging = false
                physics.omega = 28
                retarget(x(for: value))
            }
    }

    private func nudge(_ direction: Double) {
        let next = min(range.upperBound, max(range.lowerBound, value + direction * step))
        if value != next {
            value = next
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    nonisolated private static func draw(_ context: inout GraphicsContext, _ size: CGSize,
                                         thumb: CGFloat, dragging: Bool, scale: CGFloat) {
        func snap(_ value: CGFloat) -> CGFloat { Pixel.snap(value, scale) }
        func fill(_ rect: CGRect, _ color: Color) {
            context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
        }
        let x = snap(min(max(thumb, 0), size.width - 2))
        let columns = Int((size.width + 2) / 4)
        let lastLit = (0..<columns).last { CGFloat($0) * 4 + 2 <= x + 0.5 } ?? -1
        for column in 0..<columns {
            var height: CGFloat = column <= lastLit ? 8 : 4
            if dragging && (abs(column - lastLit) <= 1 || column == lastLit + 1) { height += 4 }
            let color = column > lastLit ? Tok.controlPressed
                : column > lastLit - 3 ? ((column + lastLit) % 2 == 0 ? Ramp.blue[4] : Ramp.blue[3])
                : Ramp.blue[3]
            fill(CGRect(x: CGFloat(column) * 4, y: snap((size.height - height) / 2), width: 2, height: height), color)
        }
        let height: CGFloat = dragging ? 20 : 16
        fill(CGRect(x: x, y: snap((size.height - height) / 2), width: 2, height: height), Tok.text)
    }
}
