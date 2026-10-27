import CoreGraphics
import Foundation
import SuperflowDesignSystem
import SwiftUI

public struct PixelPalette: Sendable, Equatable {
    public var lightDeep: UInt32
    public var lightMid: UInt32
    public var lightPale: UInt32
    public var darkDeep: UInt32
    public var darkMid: UInt32
    public var darkPale: UInt32

    public init(lightDeep: UInt32, lightMid: UInt32, lightPale: UInt32,
                darkDeep: UInt32, darkMid: UInt32, darkPale: UInt32) {
        self.lightDeep = lightDeep
        self.lightMid = lightMid
        self.lightPale = lightPale
        self.darkDeep = darkDeep
        self.darkMid = darkMid
        self.darkPale = darkPale
    }

    public static let blue = PixelPalette(lightDeep: 0xFFFFFF, lightMid: 0x93C5FD,
                                          lightPale: 0x2563EB, darkDeep: 0x0A0A0A,
                                          darkMid: 0x1E3A8A, darkPale: 0x2563EB)

    public func hex(tone: Int, dark: Bool) -> UInt32? {
        switch (tone, dark) {
        case (0, false): lightDeep
        case (1, false): lightMid
        case (2, false): lightPale
        case (0, true): darkDeep
        case (1, true): darkMid
        case (2, true): darkPale
        default: nil
        }
    }

    public func color(tone: Int, dark: Bool) -> Color? {
        hex(tone: tone, dark: dark).map { Color(hex: $0) }
    }
}

public enum PixelClearShape: String, Sendable, CaseIterable {
    case organic, rect
}

public struct PixelDisc: Sendable, Equatable {
    public var cells: Int
    public var grow: Double

    public init(cells: Int = 11, grow: Double = 1) {
        self.cells = max(1, cells % 2 == 0 ? cells + 1 : cells)
        self.grow = min(1, max(0, grow))
    }
}

public struct PixelFieldConfig: Sendable, Equatable {
    public var cell: CGFloat = 16
    public var seed: UInt64 = 11
    public var cover: Double = 0.5
    public var dither: Double = 0.5
    public var steps: Int = 14
    public var reveal: Double = 1
    public var drift: Double = 0
    public var collapse: Double = 0
    public var clearPadX: Double = 5
    public var clearPadY: Double = 3
    public var falloff: Double = 3
    public var clearShape: PixelClearShape = .organic
    public var disc = PixelDisc(cells: 0, grow: 0)

    public init() {}
}

public struct PixelCell: Sendable, Equatable {
    public var column: Int
    public var row: Int
    public var tone: Int

    public init(column: Int, row: Int, tone: Int) {
        self.column = column
        self.row = row
        self.tone = tone
    }
}

/// Deterministic software implementation of the DESIGN §8 field. The renderer
/// returns flat cells; the view never anti-aliases or interpolates.
public enum PixelRenderer {
    private static let thresholds: [Double] = [0.42, 0.49, 0.55, 0.61]

    public static func cells(size: CGSize, clear: [CGRect] = [],
                             config: PixelFieldConfig = PixelFieldConfig(),
                             time: Double = 0) -> [PixelCell] {
        let cell = max(2, config.cell)
        let columns = max(0, Int(size.width / cell))
        let rows = max(0, Int(size.height / cell))
        guard columns > 0, rows > 0 else { return [] }

        let frequency = 2.4 / Double(size.width)
        let shift = driftShift(config: config, size: size, time: time)
        let hole = HoleGeometry(rects: clear, padX: config.clearPadX * cell,
                                padY: config.clearPadY * cell)
        let center = CGPoint(x: Double(columns) / 2, y: Double(rows) / 2)
        let reach = (pow(center.x, 2) + pow(center.y, 2)).squareRoot()
        let ring = reach + 10 - min(1, max(0, config.collapse)) * (reach + 20)
        let revealCutoff = ceil(easeOutCubic(min(1, max(0, config.reveal))) * Double(max(1, config.steps)))
            / Double(max(1, config.steps))

        var output: [PixelCell] = []
        output.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(x: (Double(column) + 0.5) * cell,
                                    y: (Double(row) + 0.5) * cell)
                if config.reveal < 1 {
                    let order = revealOrder(column: column, row: row, columns: columns, rows: rows,
                                            seed: config.seed)
                    if order > revealCutoff { continue }
                }

                if let discTone = discTone(column: column, row: row, center: center,
                                           config: config) {
                    output.append(PixelCell(column: column, row: row, tone: discTone))
                    continue
                }

                let distance = hypot(Double(column) + 0.5 - center.x,
                                     Double(row) + 0.5 - center.y)
                let ragged = (noise(Double(column) * 0.08, Double(row) * 0.08, seed: config.seed + 21) * 2 - 1) * 7
                    + (hash(column, row, seed: config.seed + 31) * 2 - 1) * 1.5
                let edge = distance - (ring + ragged)
                guard edge <= 0 else { continue }

                let holeDistance = hole.distance(point: point, shape: config.clearShape,
                                                 seed: config.seed)
                if holeDistance <= 0 {
                    output.append(PixelCell(column: column, row: row, tone: 0))
                    continue
                }

                var value = fieldValue(column: column, row: row, cell: cell, shift: shift,
                                       frequency: frequency, config: config)
                if holeDistance < config.falloff {
                    value -= 0.9 * max(0, 1 - holeDistance / max(0.001, config.falloff))
                }
                if edge > -3 {
                    value -= 0.5 * smoothstep(-3, 0, edge)
                }
                output.append(PixelCell(column: column, row: row,
                                        tone: tone(value, column: column, row: row, config: config)))
            }
        }
        return output
    }

    private static func fieldValue(column: Int, row: Int, cell: CGFloat, shift: Double,
                                   frequency: Double, config: PixelFieldConfig) -> Double {
        var x = Double(column) + 0.5 + shift
        var y = Double(row) + 0.5
        let probe = noise(x * frequency * 1.3, y * frequency * 1.3, seed: config.seed + 7)
        if probe > 0.6 {
            x = (floor(Double(column) / 3) * 3 + 1.5)
            y = (floor(Double(row) / 3) * 3 + 1.5)
        }
        let px = x * frequency
        let py = y * frequency
        var value = 0.6 * noise(px, py, seed: config.seed)
            + 0.3 * noise(px * 2, py * 2, seed: config.seed + 1)
            + 0.1 * noise(px * 4, py * 4, seed: config.seed + 2)
        value -= (config.cover - 0.5) * 0.25
        return value
    }

    private static func tone(_ value: Double, column: Int, row: Int,
                             config: PixelFieldConfig) -> Int {
        var band = 0
        for threshold in thresholds where value > threshold { band += 1 }
        let even = config.dither >= 0.5
            ? (column + row) % 2 == 0
            : hash(column, row, seed: config.seed + 5) < config.dither
        switch band {
        case 0: return 0
        case 1: return even ? 1 : 0
        case 2: return 1
        case 3: return even ? 2 : 1
        default: return 2
        }
    }

    private static func discTone(column: Int, row: Int, center: CGPoint,
                                 config: PixelFieldConfig) -> Int? {
        guard config.disc.grow > 0, config.disc.cells > 1 else { return nil }
        let n = Double(config.disc.cells)
        let radius = n / 2 * config.disc.grow
        let dx = Double(column) + 0.5 - center.x
        let dy = Double(row) + 0.5 - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance <= radius else { return nil }
        let t = distance / (n / 2)
        var value = 0.80 - 0.22 * t * t + (hash(column, row, seed: config.seed + 41) - 0.5) * 0.12
        if t < 0.75, hash(column, row, seed: config.seed + 43) < 0.16 {
            value -= 0.17
        }
        return tone(value, column: column, row: row, config: config)
    }

    private static func revealOrder(column: Int, row: Int, columns: Int, rows: Int,
                                    seed: UInt64) -> Double {
        let nx = columns > 1 ? (Double(column) / Double(columns - 1)) * 2 - 1 : 0
        let ny = rows > 1 ? (Double(row) / Double(rows - 1)) * 2 - 1 : 0
        let radius = min(1, (nx * nx + ny * ny).squareRoot() / 2.0.squareRoot())
        return radius * 0.82 + hash(column, row, seed: seed + 3) * 0.18
    }

    private static func driftShift(config: PixelFieldConfig, size: CGSize, time: Double) -> Double {
        guard config.drift > 0 else { return 0 }
        let shift = sin(time * 2 * .pi / config.drift) * Double(size.width) / 6
        return (shift / Double(config.cell)).rounded()
    }

    static func hash(_ x: Int, _ y: Int, seed: UInt64) -> Double {
        var value = UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15
        value ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
        value ^= seed &* 0x165667B19E3779F9
        value ^= value >> 33
        value &*= 0xFF51AFD7ED558CCD
        value ^= value >> 33
        value &*= 0xC4CEB9FE1A85EC53
        value ^= value >> 33
        return Double(value & 0xFFFFFF) / Double(0xFFFFFF)
    }

    static func noise(_ x: Double, _ y: Double, seed: UInt64) -> Double {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = smoothstep(0, 1, x - floor(x))
        let fy = smoothstep(0, 1, y - floor(y))
        let a = hash(x0, y0, seed: seed)
        let b = hash(x0 + 1, y0, seed: seed)
        let c = hash(x0, y0 + 1, seed: seed)
        let d = hash(x0 + 1, y0 + 1, seed: seed)
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge0 != edge1 else { return x < edge0 ? 0 : 1 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    static func easeOutCubic(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }
}

private struct HoleGeometry {
    struct Rect {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
        var centerX: Double { (minX + maxX) / 2 }
        var centerY: Double { (minY + maxY) / 2 }
        var radiusX: Double { max(1, (maxX - minX) / 2) }
        var radiusY: Double { max(1, (maxY - minY) / 2) }
    }

    let rects: [Rect]

    init(rects: [CGRect], padX: Double, padY: Double) {
        self.rects = rects.map {
            Rect(minX: $0.minX - padX, minY: $0.minY - padY,
                 maxX: $0.maxX + padX, maxY: $0.maxY + padY)
        }
    }

    func distance(point: CGPoint, shape: PixelClearShape, seed: UInt64) -> Double {
        guard !rects.isEmpty else { return .infinity }
        var best = Double.infinity
        for rect in rects {
            if point.x >= rect.minX, point.x <= rect.maxX,
               point.y >= rect.minY, point.y <= rect.maxY { return 0 }
            let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
            let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
            var value = hypot(dx, dy)
            if shape == .organic {
                let nx = (point.x - rect.centerX) / rect.radiusX
                let ny = (point.y - rect.centerY) / rect.radiusY
                let edgeNoise = (PixelRenderer.noise(point.x / 16 * 5, point.y / 16 * 5,
                                                     seed: seed + 13) * 2 - 1) * 0.16
                let normalized = (nx * nx + ny * ny).squareRoot() - 1 - edgeNoise
                value = max(0, normalized) * min(rect.radiusX, rect.radiusY)
            }
            best = min(best, value)
        }
        return best
    }
}

public struct PixelField: View {
    private let clear: [CGRect]
    private let config: PixelFieldConfig
    private let palette: PixelPalette
    private let label: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public init(clear: [CGRect] = [], config: PixelFieldConfig = PixelFieldConfig(),
                palette: PixelPalette = .blue, accessibilityLabel: String? = nil) {
        self.clear = clear
        self.config = config
        self.palette = palette
        self.label = accessibilityLabel
    }

    public var body: some View {
        let effective = effectiveConfig
        let still = effective.drift == 0 || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { timeline in
            let time = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for cell in PixelRenderer.cells(size: size, clear: clear, config: effective,
                                                time: time) {
                    guard let color = palette.color(tone: cell.tone, dark: scheme == .dark) else { continue }
                    let rect = CGRect(x: CGFloat(cell.column) * effective.cell,
                                      y: CGFloat(cell.row) * effective.cell,
                                      width: effective.cell, height: effective.cell)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    private var effectiveConfig: PixelFieldConfig {
        guard reduceMotion else { return config }
        var value = config
        value.reveal = 1
        value.drift = 0
        value.disc.grow = 1
        return value
    }
}
