import SuperflowDesignSystem
import SwiftUI

/// Three tones only. `nil` means deep: draw nothing and let the page show through.
public enum Tone {
    public static let bands: [CGFloat] = [0.42, 0.49, 0.55, 0.61]

    public static func color(_ value: CGFloat, _ column: Int, _ row: Int, dark: Bool) -> Color? {
        let mid = dark ? Color(hex: 0x1E3A8A) : Color(hex: 0x93C5FD)
        let pale = Color(hex: 0x2563EB)
        let even = (column + row) % 2 == 0
        switch bands.firstIndex(where: { value < $0 }) ?? 4 {
        case 0: return nil
        case 1: return even ? mid : nil
        case 2: return mid
        case 3: return even ? pale : mid
        default: return pale
        }
    }
}

/// The brand. Odd cell counts: 5 hero, 7 compact, 11 default. Snapped to device pixels.
public struct PixelStop: View {
    private let cells: Int
    private let cell: CGFloat
    private let seed: UInt32
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme

    public init(cells: Int = 5, cell: CGFloat = 1.5, seed: UInt32 = 11) {
        self.cells = cells
        self.cell = cell
        self.seed = seed
    }

    var count: Int { cells % 2 == 0 ? cells + 1 : cells }

    private var unit: CGFloat {
        max(1 / scale, (cell * scale).rounded() / scale)
    }

    public var body: some View {
        let u = unit
        let n = count
        let dark = scheme == .dark
        let seed = seed
        Canvas { context, _ in
            let centre = CGFloat(n) / 2
            for row in 0..<n {
                for column in 0..<n {
                    let dx = CGFloat(column) + 0.5 - centre
                    let dy = CGFloat(row) + 0.5 - centre
                    let radius = (dx * dx + dy * dy).squareRoot()
                    guard radius <= centre else { continue }
                    let t = radius / centre
                    var value = 0.80 - 0.22 * t * t
                        + (PixelStop.hash(column, row, seed) - 0.5) * 0.12
                    if t < 0.75, PixelStop.hash(column, row, seed &+ 5) < 0.16 {
                        value -= 0.17
                    }
                    guard let color = Tone.color(value, column, row, dark: dark) else { continue }
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * u, y: CGFloat(row) * u,
                                    width: u, height: u)),
                        with: .color(color),
                        style: FillStyle(antialiased: false)
                    )
                }
            }
        }
        .frame(width: CGFloat(n) * u, height: CGFloat(n) * u)
        .accessibilityHidden(true)
    }

    static func hash(_ x: Int, _ y: Int, _ seed: UInt32) -> CGFloat {
        var value = UInt32(truncatingIfNeeded: x) &* 374761393
            &+ UInt32(truncatingIfNeeded: y) &* 668265263
            &+ seed &* 2246822519
        value = (value ^ (value >> 13)) &* 1274126177
        value ^= value >> 16
        return CGFloat(value) / CGFloat(UInt32.max)
    }
}
