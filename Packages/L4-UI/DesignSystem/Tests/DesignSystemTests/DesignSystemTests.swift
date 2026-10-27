import SwiftUI
import XCTest
@testable import SuperflowDesignSystem

final class DesignSystemTests: XCTestCase {
    func testSurfaceLadderMatchesDesignSpec() {
        XCTAssertEqual(Tok.Hex.bgLight, 0xF4F4F4)
        XCTAssertEqual(Tok.Hex.bgDark, 0x0A0A0A)
        XCTAssertEqual(Tok.Hex.surfaceLight, 0xFFFFFF)
        XCTAssertEqual(Tok.Hex.surfaceDark, 0x171717)
        XCTAssertEqual(Tok.Hex.wellLight, 0xEDEDED)
        XCTAssertEqual(Tok.Hex.wellDark, 0x0F0F0F)
        XCTAssertEqual(Tok.Hex.controlLight, 0xEBEBEB)
        XCTAssertEqual(Tok.Hex.controlDark, 0x1F1F1F)
        XCTAssertEqual(Tok.Hex.controlHoverDark, 0x262626)
        XCTAssertEqual(Tok.Hex.controlPressedDark, 0x2E2E2E)
        XCTAssertEqual(Tok.Hex.textLight, 0x0A0A0A)
        XCTAssertEqual(Tok.Hex.textDark, 0xFAFAFA)
        XCTAssertEqual(Tok.Hex.text2Light, 0x666666)
        XCTAssertEqual(Tok.Hex.text2Dark, 0xA3A3A3)
    }

    /// Each dark step must be distinguishable from the one below it.
    func testDarkLadderStepsAreDistinct() {
        let ladder = [Tok.Hex.bgDark, Tok.Hex.wellDark, Tok.Hex.surfaceDark,
                      Tok.Hex.controlDark, Tok.Hex.controlHoverDark, Tok.Hex.controlPressedDark]
        XCTAssertEqual(Set(ladder).count, ladder.count)
        for pair in zip(ladder, ladder.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1 - pair.0, 4)
        }
    }

    /// Blue 600 base, blue 500/700 for hover, blue 700 pressed. Nothing darker, ever.
    func testAccentIsBlue600Everywhere() {
        XCTAssertEqual(Tok.Hex.accent, 0x2563EB)
        XCTAssertEqual(Tok.Hex.accentHoverLight, 0x1D4ED8)
        XCTAssertEqual(Tok.Hex.accentHoverDark, 0x3B82F6)
        XCTAssertEqual(Tok.Hex.accentPressed, 0x1D4ED8)
        XCTAssertEqual(Tok.Hex.accentTextDark, 0x60A5FA)
        XCTAssertEqual(Tok.Hex.accentSoftLight, 0xDBEAFE)
    }

    func testHexColorConvertsToRGB() {
        let rgb = RGB(hex: 0x2563EB)
        XCTAssertEqual(rgb.red, 37.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(rgb.green, 99.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(rgb.blue, 235.0 / 255, accuracy: 0.0001)
    }

    func testBadgeCycleWrapsBothWays() {
        XCTAssertEqual(BadgeVariant.at(0), .blue)
        XCTAssertEqual(BadgeVariant.at(1), .green)
        XCTAssertEqual(BadgeVariant.at(8), .rose)
        XCTAssertEqual(BadgeVariant.at(9), .blue)
        XCTAssertEqual(BadgeVariant.at(10), .green)
        XCTAssertEqual(BadgeVariant.at(-1), .rose)
        XCTAssertEqual(BadgeVariant.cycle.count, 9)
    }

    func testBadgeRampsMatchDesignSpec() {
        XCTAssertEqual(BadgeVariant.blue.ramp.c600, 0x2563EB)
        XCTAssertEqual(BadgeVariant.blue.ramp.c100, 0xDBEAFE)
        XCTAssertEqual(BadgeVariant.blue.ramp.c700, 0x1D4ED8)
        XCTAssertEqual(BadgeVariant.rose.ramp.c600, 0xE11D48)
        XCTAssertEqual(BadgeVariant.green.ramp.c700, 0x15803D)
        XCTAssertEqual(BadgeVariant.neutral.ramp.c600, 0x525252)
    }

    func testBadgeSizes() {
        XCTAssertEqual(BadgeSize.lg.fontSize, 13)
        XCTAssertEqual(BadgeSize.md.fontSize, 12)
        XCTAssertEqual(BadgeSize.sm.fontSize, 10)
        XCTAssertEqual(BadgeSize.md.minHeight, 20)
    }

    func testDotCycleAndColors() {
        XCTAssertEqual(DotTone.cycle, [.blue, .green, .orange, .purple])
        XCTAssertEqual(DotTone.at(4), .blue)
        XCTAssertEqual(DotTone.at(-1), .purple)
        XCTAssertEqual(DotTone.blue.hex, 0x2563EB)
        XCTAssertEqual(DotTone.neutral.hex, 0x525252)
    }

    func testSpacingAndRadii() {
        XCTAssertEqual(Space.grid, 4)
        XCTAssertEqual(Space.pagePadding, 32)
        XCTAssertEqual(Space.cardPadding, 20)
        XCTAssertEqual(Space.cardPaddingDense, 16)
        XCTAssertEqual(Space.sectionGap, 32)
        XCTAssertEqual(Space.proseMaxWidth, 720)
        XCTAssertEqual(Space.pageMaxWidth, 880)
        XCTAssertEqual(Radius.card, 16)
        XCTAssertEqual(Radius.nested, 12)
        XCTAssertEqual(Radius.field, 8)
        XCTAssertEqual(Radius.badge, 8)
        XCTAssertEqual(Radius.chip, 6)
        XCTAssertEqual(Radius.islandCompact, 22)
        XCTAssertEqual(Radius.islandExpanded, 26)
        XCTAssertEqual(ControlHeight.small, 24)
        XCTAssertEqual(ControlHeight.regular, 28)
        XCTAssertEqual(ControlHeight.large, 32)
        XCTAssertEqual(Layout.sidebarWidth, 220)
        XCTAssertEqual(Layout.sidebarMin, 200)
        XCTAssertEqual(Layout.sidebarMax, 280)
        XCTAssertEqual(Layout.windowDefaultWidth, 960)
        XCTAssertEqual(Layout.windowDefaultHeight, 620)
        XCTAssertEqual(Layout.windowMinWidth, 880)
        XCTAssertEqual(Layout.windowMinHeight, 560)
        XCTAssertEqual(Layout.onboardingWidth, 640)
        XCTAssertEqual(Layout.onboardingHeight, 520)
        XCTAssertEqual(Layout.islandDragThreshold, 4)
        XCTAssertEqual(Layout.islandTopInset, 6)
    }

    func testMotionNumbers() {
        XCTAssertEqual(Motion.stagger, 0.07)
        XCTAssertEqual(Motion.staggerDelay(index: 3), 0.21, accuracy: 0.0001)
    }

    func testTypeScale() {
        XCTAssertEqual(TypeScale.displaySize, 40)
        XCTAssertEqual(TypeScale.displaySSize, 28)
        XCTAssertEqual(TypeScale.metricSize, 28)
        XCTAssertEqual(TypeScale.titleSize, 22)
        XCTAssertEqual(TypeScale.headlineSize, 15)
        XCTAssertEqual(TypeScale.bodySize, 13)
        XCTAssertEqual(TypeScale.secondarySize, 12)
        XCTAssertEqual(TypeScale.displayTracking, -2)
        XCTAssertEqual(TypeScale.displaySTracking, -1.4)
    }

    func testOpacityValues() {
        XCTAssertEqual(Opacity.disabled, 0.4)
        XCTAssertEqual(Opacity.pressScale, 0.98)
    }
}
