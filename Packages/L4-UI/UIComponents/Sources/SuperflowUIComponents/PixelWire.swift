import SuperflowDesignSystem
import SwiftUI

public struct PixelWire: View, Animatable {
    nonisolated public var progress: Double
    private let horizontal: Bool
    nonisolated public var animatableData: Double { get { progress } set { progress = newValue } }

    public init(progress: Double, horizontal: Bool = false) {
        self.progress = progress
        self.horizontal = horizontal
    }

    public var body: some View {
        let lit = min(4, max(0, Int((progress * 4).rounded(.down))))
        Canvas { context, _ in
            for index in 0..<4 {
                let rect = horizontal
                    ? CGRect(x: CGFloat(index) * 6, y: 0, width: 4, height: 4)
                    : CGRect(x: 0, y: CGFloat(index) * 6, width: 4, height: 4)
                context.fill(Path(rect), with: .color(index < lit
                    ? (index == lit - 1 ? Ramp.blue[4] : Ramp.blue[3]) : Tok.controlPressed),
                    style: FillStyle(antialiased: false))
            }
        }
        .frame(width: horizontal ? 22 : 4, height: horizontal ? 4 : 22)
        .accessibilityHidden(true)
    }
}
