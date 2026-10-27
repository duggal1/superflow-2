import CoreGraphics
import XCTest
@testable import SuperflowUIComponents

final class PixelDiscFlightTests: XCTestCase {
    private let canvas = CGSize(width: 640, height: 520)
    /// The slot the onboarding reserves after the title.
    private var slot: CGRect {
        CGRect(x: 300, y: 100, width: PixelDiscFlight.slotSide, height: PixelDiscFlight.slotSide)
    }

    private func flight(grow: Double = 1, travel: Double = 0,
                        arc: CGFloat = 0.06) -> PixelDiscFlight {
        PixelDiscFlight(canvas: canvas, slot: slot, grow: grow, travel: travel, arc: arc)
    }

    func testSlotIsTheLandedDiscWidth() {
        XCTAssertEqual(PixelDiscFlight.slotSide, 7.5)
    }

    func testEvenCellCountsAreForcedOdd() {
        let even = PixelDiscFlight(canvas: canvas, slot: slot, grow: 1, travel: 1, cells: 8)
        XCTAssertEqual(even.count, 9)
        XCTAssertEqual(flight().count, 5)
    }

    func testDiscStartsAtTheFieldCentreBeforeItTravels() {
        let disc = flight(grow: 1, travel: 0)
        XCTAssertEqual(disc.center.x, canvas.width / 2, accuracy: 0.0001)
        XCTAssertEqual(disc.center.y, canvas.height / 2, accuracy: 0.0001)
        XCTAssertEqual(disc.side, 5 * 16, accuracy: 0.0001)
    }

    func testDiscLandsExactlyOnTheSlotAtTheSlotsOwnCellSize() {
        let disc = PixelDiscFlight.landed(canvas: canvas, slot: slot)
        XCTAssertEqual(disc.center.x, slot.midX, accuracy: 0.0001)
        XCTAssertEqual(disc.center.y, slot.midY, accuracy: 0.0001)
        XCTAssertEqual(disc.cell, PixelDiscFlight.landedCell, accuracy: 0.0001)
        XCTAssertEqual(disc.side, slot.width, accuracy: 0.0001)
        XCTAssertTrue(disc.hasLanded)
    }

    func testDiscShrinksMonotonicallyAlongTheFlight() {
        let sides = stride(from: 0.0, through: 1.0, by: 0.1).map { flight(travel: $0).side }
        for pair in zip(sides, sides.dropFirst()) {
            XCTAssertLessThan(pair.1, pair.0)
        }
        XCTAssertEqual(sides.first ?? 0, 5 * 16, accuracy: 0.0001)
        XCTAssertEqual(sides.last ?? 0, 7.5, accuracy: 0.0001)
    }

    func testDiscRisesAboveTheStraightLineMidFlight() {
        let straight = flight(travel: 0.5, arc: 0)
        let arced = flight(travel: 0.5, arc: 0.06)
        XCTAssertEqual(arced.center.x, straight.center.x, accuracy: 0.0001)
        XCTAssertLessThan(arced.center.y, straight.center.y)
        XCTAssertEqual(straight.center.y - arced.center.y, canvas.height * 0.06, accuracy: 0.0001)
    }

    func testArcIsZeroAtBothEnds() {
        XCTAssertEqual(flight(travel: 0, arc: 0.06).center.y,
                       flight(travel: 0, arc: 0).center.y, accuracy: 0.0001)
        XCTAssertEqual(flight(travel: 1, arc: 0.06).center.y,
                       flight(travel: 1, arc: 0).center.y, accuracy: 0.0001)
    }

    func testGrowScalesTheDiscFromNothing() {
        XCTAssertEqual(flight(grow: 0).side, 0, accuracy: 0.0001)
        XCTAssertEqual(flight(grow: 0.5).side, 5 * 8, accuracy: 0.0001)
    }

    func testTravelAndGrowAreClamped() {
        let over = flight(grow: 4, travel: 4)
        XCTAssertEqual(over.side, 7.5, accuracy: 0.0001)
        let under = flight(grow: -2, travel: -2)
        XCTAssertEqual(under.side, 0, accuracy: 0.0001)
    }
}
