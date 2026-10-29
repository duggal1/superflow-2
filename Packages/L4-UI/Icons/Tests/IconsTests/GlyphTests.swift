import AppKit
import XCTest
@testable import SuperflowIcons

final class GlyphTests: XCTestCase {
    func testEveryGlyphMapsToAnAvailableSystemSymbol() {
        for glyph in Glyph.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: nil),
                            "missing SF Symbol for \(glyph.rawValue)")
        }
    }

    func testFallbackSymbolsAreBare() {
        for glyph in Glyph.allCases {
            let name = glyph.rawValue
            XCTAssertFalse(name.hasSuffix(".circle"), "\(name) draws its own enclosure")
            XCTAssertFalse(name.hasSuffix(".square"), "\(name) draws its own enclosure")
            XCTAssertFalse(name.hasSuffix(".rectangle"), "\(name) draws its own enclosure")
            XCTAssertFalse(name.hasPrefix("sparkles"), "the AI sparkle is banned")
            XCTAssertFalse(name.hasPrefix("wand."), "the AI sparkle is banned")
        }
    }

    @MainActor
    func testSelectedSidebarIconsUseHugeicons() {
        for glyph: Glyph in [.dashboard, .dictionary, .meetings, .models] {
            XCTAssertNotNil(HugeIcon.image(for: glyph))
        }
    }

    @MainActor
    func testHugeIconsAreBundledAndLoadable() {
        for glyph in HugeIcon.glyphs {
            XCTAssertNotNil(HugeIcon.image(for: glyph), "Missing Hugeicon for \(glyph)")
        }
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
