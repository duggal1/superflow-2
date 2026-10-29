import AppKit
import XCTest
@testable import SuperflowIcons

final class GlyphTests: XCTestCase {
    func testEveryGlyphMapsToAnAvailableSystemSymbol() {
        for glyph in Icon.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: nil),
                            "missing SF Symbol for \(glyph.rawValue)")
        }
    }

    func testSettingsAndSidebarSymbolsHaveDistinctMeanings() {
        let sidebar: [Icon] = [.dashboard, .history, .dictionary, .shortcuts, .meetings, .models, .settings]
        let dictation: [Icon] = [.speechModel, .noiseSuppression, .cleanup, .keyboard, .liveText,
                                 .handTap, .doubleTap, .settingMeeting]
        let advanced: [Icon] = [.typingSpeed, .interactiveDeadline, .backgroundDeadline,
                                .settingWorkers, .settingCompute]
        for group in [sidebar + dictation, sidebar + advanced] {
            XCTAssertEqual(Set(group.map(\.symbolName)).count, group.count)
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
        XCTAssertTrue(svg.contains("viewBox=\"0 0 163.3 108\""))
        XCTAssertTrue(svg.contains("#8EE000"))
        XCTAssertNotNil(NSImage(contentsOf: url))
    }
}
