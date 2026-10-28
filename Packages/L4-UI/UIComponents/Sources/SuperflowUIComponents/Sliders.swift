import SuperflowDesignSystem
import SwiftUI

/// Track 4, Blue 600 fill, `Tok.text` thumb. The thumb follows the pointer
/// continuously; the value snaps to the step underneath, and on release the
/// thumb settles onto the step. Fixed 280 wide and a 64 readout, so every track
/// in Settings starts on the same x.
public struct AppSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let unit: String

    @Environment(\.displayScale) private var scale
    @Environment(\.isEnabled) private var enabled
    @State private var raw: Double?

    private let thumb: CGFloat = 16
    private let track: CGFloat = 4

    public init(value: Binding<Double>, in range: ClosedRange<Double>,
                step: Double = 50, unit: String) {
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: 16) {
            GeometryReader { geo in
                let usable = max(1, geo.size.width - thumb)
                let span = range.upperBound - range.lowerBound
                let fraction = span > 0 ? ((raw ?? value) - range.lowerBound) / span : 0
                let x = Pixel.snap(usable * CGFloat(min(max(fraction, 0), 1)), scale)
                ZStack(alignment: .leading) {
                    Capsule().fill(Tok.controlPressed).frame(height: track)
                    Capsule().fill(Tok.accent).frame(width: x + thumb / 2, height: track)
                    Circle().fill(Tok.text)
                        .frame(width: thumb, height: thumb)
                        .scaleEffect(raw != nil ? 1.125 : 1)
                        .keyboardFocusRing(radius: 11)
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let t = min(max((gesture.location.x - thumb / 2) / usable, 0), 1)
                        let live = range.lowerBound + Double(t) * span
                        raw = live
                        value = min(max((live / step).rounded() * step, range.lowerBound),
                                    range.upperBound)
                    }
                    .onEnded { _ in
                        withAnimation(.snappy(duration: 0.18)) { raw = nil }
                    })
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) {
                    value = max(range.lowerBound, value - step)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    value = min(range.upperBound, value + step)
                    return .handled
                }
            }
            .frame(height: 32)
            .clickable(enabled)

            Text("\(Int(value)) \(unit)")
                .appType(.body)
                .monospacedDigit()
                .foregroundStyle(Tok.text2)
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.15), value: value)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: 280)
        .opacity(enabled ? 1 : Opacity.disabled)
        .accessibilityRepresentation {
            // The one allowed native Slider: VoiceOver only.
            Slider(value: $value, in: range, step: step)
        }
        .pixelAudit("AppSlider")
    }
}
