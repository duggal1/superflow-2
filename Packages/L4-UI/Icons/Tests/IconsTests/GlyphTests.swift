import AppKit
import XCTest
@testable import SuperflowIcons

final class GlyphTests: XCTestCase {
    func testEveryGlyphMapsToAnAvailableSystemSymbol() {
        for glyph in Glyph.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: glyph.rawValue, accessibilityDescription: nil),
                            "missing SF Symbol for \(glyph.rawValue)")
        }
    }

    func testSymbolsAreBareAndNotFromAForeignFamily() {
        for glyph in Glyph.allCases {
            let name = glyph.rawValue
            XCTAssertFalse(name.hasSuffix(".circle"), "\(name) draws its own enclosure")
            XCTAssertFalse(name.hasSuffix(".square"), "\(name) draws its own enclosure")
            XCTAssertFalse(name.hasSuffix(".rectangle"), "\(name) draws its own enclosure")
            XCTAssertFalse(name.hasPrefix("sparkles"), "the AI sparkle is banned")
            XCTAssertFalse(name.hasPrefix("wand."), "the AI sparkle is banned")
        }
    }

    /// The sidebar uses the specific Apple symbol for each page, not the stock
    /// pick: a plotted trend line, a transcript with a play head, people plus
    /// sound, a chip, and three tuning sliders. Pinned so a later edit cannot
    /// quietly drift back to the generic set.
    func testSidebarGlyphsMatchTheProductStructure() {
        XCTAssertEqual(Glyph.dashboard.rawValue, "chart.xyaxis.line")
        XCTAssertEqual(Glyph.history.rawValue, "text.line.first.and.arrowtriangle.forward")
        XCTAssertEqual(Glyph.dictionary.rawValue, "character.book.closed")
        XCTAssertEqual(Glyph.shortcuts.rawValue, "command")
        XCTAssertEqual(Glyph.meetings.rawValue, "person.2.wave.2")
        XCTAssertEqual(Glyph.models.rawValue, "memorychip")
        XCTAssertEqual(Glyph.settings.rawValue, "slider.horizontal.3")
    }

    func testWeightsStayWithinDesignLaw() {
        XCTAssertEqual(IconWeight.regular.fontWeight, .regular)
        XCTAssertEqual(IconWeight.medium.fontWeight, .medium)
    }

    /// The owner replaced the logo; the bundled mark must stay and stay loadable.
    @MainActor
    func testBrandMarkIsBundled() throws {
        let url = try XCTUnwrap(BrandMarkView.resourceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(NSImage(contentsOf: url))
    }

    @MainActor
    func testNVIDIAProviderMarkIsBundled() throws {
        let url = try XCTUnwrap(NVIDIAIcon.resourceURL)
        let svg = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(svg.contains("viewBox=\"56.781 31.512 248.899 164.698\""))
        XCTAssertTrue(svg.contains("#87cf02"))
        XCTAssertNotNil(NSImage(contentsOf: url))
    }
}
