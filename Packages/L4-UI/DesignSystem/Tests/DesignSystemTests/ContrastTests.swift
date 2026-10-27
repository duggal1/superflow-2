import XCTest
@testable import SuperflowDesignSystem

/// Automated accessibility gate for the color tokens. With no borders, the fill
/// carries the shape, so text must hold AA on every surface step it can sit on.
final class ContrastTests: XCTestCase {
    /// WCAG 2.1 relative luminance.
    private func luminance(_ rgb: RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }

    private func ratio(_ foreground: RGB, _ background: RGB) -> Double {
        let a = luminance(foreground)
        let b = luminance(background)
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func assertContrast(_ foreground: RGB, _ background: RGB, atLeast floor: Double,
                                _ label: String, file: StaticString = #filePath,
                                line: UInt = #line) {
        let value = ratio(foreground, background)
        XCTAssertGreaterThanOrEqual(value, floor,
            "\(label) contrast is \(String(format: "%.2f", value)):1, below \(floor):1",
            file: file, line: line)
    }

    private var lightSurfaces: [(String, UInt32)] {
        [("bg", Tok.Hex.bgLight), ("surface", Tok.Hex.surfaceLight),
         ("well", Tok.Hex.wellLight), ("control", Tok.Hex.controlLight)]
    }

    private var darkSurfaces: [(String, UInt32)] {
        [("bg", Tok.Hex.bgDark), ("surface", Tok.Hex.surfaceDark),
         ("well", Tok.Hex.wellDark), ("control", Tok.Hex.controlDark)]
    }

    func testPrimaryTextMeetsAAANormalInBothSchemes() {
        for (name, background) in lightSurfaces {
            assertContrast(RGB(hex: Tok.Hex.textLight), RGB(hex: background), atLeast: 7,
                           "primary text (light/\(name))")
        }
        for (name, background) in darkSurfaces {
            assertContrast(RGB(hex: Tok.Hex.textDark), RGB(hex: background), atLeast: 7,
                           "primary text (dark/\(name))")
        }
    }

    func testSecondaryTextMeetsAAOnEverySurface() {
        for (name, background) in lightSurfaces {
            assertContrast(RGB(hex: Tok.Hex.text2Light), RGB(hex: background), atLeast: 4.5,
                           "secondary text (light/\(name))")
        }
        for (name, background) in darkSurfaces {
            assertContrast(RGB(hex: Tok.Hex.text2Dark), RGB(hex: background), atLeast: 4.5,
                           "secondary text (dark/\(name))")
        }
    }

    func testAccentLinkTextMeetsAA() {
        assertContrast(RGB(hex: Tok.Hex.accentTextLight), RGB(hex: Tok.Hex.bgLight), atLeast: 4.5,
                       "accent text (light)")
        assertContrast(RGB(hex: Tok.Hex.accentTextDark), RGB(hex: Tok.Hex.bgDark), atLeast: 4.5,
                       "accent text (dark)")
    }

    func testLabelOnAccentFillMeetsAA() {
        assertContrast(RGB(hex: Tok.Hex.onAccent), RGB(hex: Tok.Hex.accent), atLeast: 4.5,
                       "onAccent over accent")
    }

    /// text.3 was removed; there is no decorative third text level to exempt.
    func testThereIsNoThirdTextLevel() {
        let mirrored = Mirror(reflecting: Tok.Hex.self)
        let names = mirrored.children.compactMap(\.label)
        XCTAssertFalse(names.contains("text3Light"))
        XCTAssertFalse(names.contains("text3Dark"))
    }
}
