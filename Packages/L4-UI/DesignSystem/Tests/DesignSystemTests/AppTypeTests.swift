import SwiftUI
import CoreText
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
        XCTAssertEqual(AppType.body.tracking, 0)
        XCTAssertEqual(AppType.label.tracking, 0)
        XCTAssertEqual(AppType.reading.tracking, 0)
        XCTAssertEqual(AppType.title.tracking, 0)
        XCTAssertEqual(AppType.metric.tracking, 0)

        XCTAssertEqual(AppFont.textWeight, 400)
        XCTAssertEqual(AppFont.emphasisWeight, 400)
        XCTAssertEqual(AppType.body.weight, 400)
        XCTAssertEqual(AppType.reading.weight, 400)
        XCTAssertEqual(AppType.label.weight, 400)
        XCTAssertEqual(AppType.title.weight, 400)
        XCTAssertEqual(AppType.metric.weight, 400)
    }

    func testIslandUsesSmallerTighterTypeAtWeight350() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("App/Resources/Fonts/AlbertSans-Variable.ttf")
        _ = CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        let tag = "wght".utf8.reduce(0) { ($0 << 8) | Int($1) }
        for role in AppType.allCases {
            XCTAssertLessThan(role.size(in: .island), role.size)
            XCTAssertLessThanOrEqual(role.tracking(in: .island), role.tracking)
            let descriptor = NSFontDescriptor(fontAttributes: [.name: AppFont.islandName, .variation: [tag: role.weight(in: .island)]])
            let font = try XCTUnwrap(NSFont(descriptor: descriptor, size: role.size(in: .island)))
            XCTAssertTrue(font.fontName.hasPrefix("AlbertSans"))
            let variation = try XCTUnwrap(CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber])
            XCTAssertEqual(variation[NSNumber(value: tag)]?.doubleValue ?? -1, 350, accuracy: 0.1)
        }
    }

    func testReadingAndLabelDigitsRender() throws {
        XCTAssertGreaterThan(try digitWidth("1234567890", role: .body), 0)
        XCTAssertGreaterThan(try digitWidth("1234567890", role: .label), 0)
    }

    func testBundledInstrumentSansUsesRequestedVariableWeights() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("App/Resources/Fonts/InstrumentSans-Variable.ttf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        _ = CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        for weight in [AppFont.textWeight, AppFont.emphasisWeight] {
            let font = Typography.nsUIFont(15, weight: weight)
            XCTAssertTrue(font.fontName.hasPrefix("InstrumentSans"), font.fontName)
            let axes = try XCTUnwrap(CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber])
            let tag = "wght".utf8.reduce(0) { ($0 << 8) | Int($1) }
            XCTAssertEqual(axes[NSNumber(value: tag)]?.doubleValue ?? 400, Double(weight), accuracy: 0.1)
        }
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
