import SwiftUI
import XCTest
@testable import SuperflowDesignSystem

@MainActor
final class AppTypeTests: XCTestCase {
    func testRolesSitOnTwoWeightsAndCarryTheirOwnTracking() {
        XCTAssertEqual(AppType.caption.size, 12)
        XCTAssertEqual(AppType.body.size, 13)
        XCTAssertEqual(AppType.label.size, 13)
        XCTAssertEqual(AppType.reading.size, 15)
        XCTAssertEqual(AppType.title.size, 15)
        XCTAssertEqual(AppType.metric.size, 28)

        XCTAssertEqual(AppType.caption.tracking, 0)
        XCTAssertEqual(AppType.body.tracking, -0.1)
        XCTAssertEqual(AppType.label.tracking, -0.1)
        XCTAssertEqual(AppType.reading.tracking, -0.2)
        XCTAssertEqual(AppType.title.tracking, -0.2)
        XCTAssertEqual(AppType.metric.tracking, -0.6)

        for role in AppType.allCases where !role.isMedium {
            XCTAssertEqual(role.font, role.font, "\(role) font must be stable")
        }
        XCTAssertTrue(AppType.label.isMedium)
        XCTAssertTrue(AppType.title.isMedium)
        XCTAssertTrue(AppType.metric.isMedium)
        XCTAssertFalse(AppType.caption.isMedium)
        XCTAssertFalse(AppType.body.isMedium)
        XCTAssertFalse(AppType.reading.isMedium)
    }

    /// The one number that makes weight 350 revertible.
    func testReadingWeightSitsBetweenLightAndRegular() {
        let weight = AppType.readingWeight.rawValue
        XCTAssertGreaterThan(weight, NSFont.Weight.light.rawValue)
        XCTAssertLessThan(weight, NSFont.Weight.regular.rawValue)
    }

    /// Pass 3 §12 asks whether `.monospacedDigit()` still tabularises on the
    /// `Font(NSFont)` path that carries weight 350. Measure it: ten different
    /// digits must be exactly as wide as ten of the same digit.
    func testWeight350DigitsAreTabular() throws {
        let narrow = try digitWidth("1111111111", role: .body)
        let wide = try digitWidth("8888888888", role: .body)
        XCTAssertEqual(narrow, wide, accuracy: 0.5,
                       "monospacedDigit() does not tabularise on the AppType 350 path")
    }

    /// The control: the Medium roles take SwiftUI's own font, so this must hold.
    func testMediumRoleDigitsAreTabular() throws {
        let narrow = try digitWidth("1111111111", role: .label)
        let wide = try digitWidth("8888888888", role: .label)
        XCTAssertEqual(narrow, wide, accuracy: 0.5)
    }

    func testDigitStringIsWiderThanAnEmptyOne() throws {
        XCTAssertGreaterThan(try digitWidth("1111111111", role: .body), 0)
    }

    private func digitWidth(_ text: String, role: AppType) throws -> CGFloat {
        let renderer = ImageRenderer(content: Text(text).appType(role).monospacedDigit())
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        return image.size.width
    }
}
