import CoreGraphics
import SuperflowDesignSystem
import SwiftUI

/// Frames the slot the disc lands on. The marker is invisible and zero-weight to the
/// eye; the disc is drawn by the field, so there is exactly one dot on the screen.
public struct PixelSlotKey: PreferenceKey {
    public static let defaultValue: Anchor<CGRect>? = nil

    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

public extension View {
    /// Marks the live slot after the title. Measured at layout, so re-padding or
    /// re-sizing the title moves the dot with it (DESIGN §13.7).
    func pixelSlot() -> some View {
        anchorPreference(key: PixelSlotKey.self, value: .bounds) { $0 }
    }
}

/// §13.6 and §13.7. The ring collapses, the disc grows at the centre of the field,
/// then travels along an arc to the slot. `grow` and `travel` are the only inputs,
/// and the onboarding advances them in whole steps so every frame lands on device
/// pixels — nothing tweens, nothing is anti-aliased.
public struct PixelDiscFlight: Equatable, Sendable {
    /// Odd, so the disc has a centre column and row. The same 5 × 1.5 stop every
    /// page title draws, so the brand mark is one size everywhere (§13.7).
    public static let cells = 5
    /// The landed cell size. `slotSide` is what the title reserves for the dot.
    public static let landedCell: CGFloat = 1.5
    public static var slotSide: CGFloat { CGFloat(cells) * landedCell }

    public var cells: Int
    /// The field's own cell, which is the size the disc grows to before it travels.
    public var homeCell: CGFloat
    /// The field's size, in points.
    public var canvas: CGSize
    /// Measured live, in canvas coordinates.
    public var slot: CGRect
    /// 0...1, from nothing to the field's cell.
    public var grow: Double
    /// 0...1, from the field's centre to the slot.
    public var travel: Double
    /// Lift at the midpoint, as a fraction of the canvas height.
    public var arc: CGFloat

    public init(canvas: CGSize,
                slot: CGRect,
                grow: Double,
                travel: Double,
                cells: Int = PixelDiscFlight.cells,
                homeCell: CGFloat = 16,
                arc: CGFloat = 0.06) {
        self.cells = cells % 2 == 0 ? cells + 1 : max(1, cells)
        self.canvas = canvas
        self.slot = slot
        self.grow = grow
        self.travel = travel
        self.homeCell = homeCell
        self.arc = arc
    }

    /// The state Reduce Motion renders, and the state the flight ends on.
    public static func landed(canvas: CGSize, slot: CGRect,
                              cells: Int = PixelDiscFlight.cells,
                              homeCell: CGFloat = 16) -> PixelDiscFlight {
        PixelDiscFlight(canvas: canvas, slot: slot, grow: 1, travel: 1,
                        cells: cells, homeCell: homeCell)
    }

    public var count: Int { cells % 2 == 0 ? cells + 1 : cells }

    private var grown: CGFloat { homeCell * CGFloat(min(max(grow, 0), 1)) }
    private var moved: CGFloat { CGFloat(min(max(travel, 0), 1)) }

    /// The field's cell while it grows, then the slot's own cell: `slotSize / N`,
    /// so at travel 1 the disc is exactly as wide as the slot and reads as the
    /// full stop rather than as a mark sitting next to it.
    public var cell: CGFloat {
        let landed = slot.width / CGFloat(count)
        return grown + (landed - grown) * moved
    }

    public var side: CGFloat { CGFloat(count) * cell }

    /// Centre of the field, centre of the slot, and a sine arc between them.
    public var center: CGPoint {
        let from = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let to = CGPoint(x: slot.midX, y: slot.midY)
        return CGPoint(x: from.x + (to.x - from.x) * moved,
                       y: from.y + (to.y - from.y) * moved
                           - sin(.pi * moved) * canvas.height * arc)
    }

    /// True once the disc has settled onto the slot.
    public var hasLanded: Bool { travel >= 1 }
}

/// Draws the travelling disc with the same tone map as the pixel full stop, so the
/// thing that lands is the thing that was flying. (`PixelDisc` is the field's own
/// config type; this is the view.)
public struct PixelDiscFlightView: View {
    private let flight: PixelDiscFlight

    public init(_ flight: PixelDiscFlight) {
        self.flight = flight
    }

    public var body: some View {
        PixelStop(cells: flight.cells, cell: flight.cell)
            .position(flight.center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
