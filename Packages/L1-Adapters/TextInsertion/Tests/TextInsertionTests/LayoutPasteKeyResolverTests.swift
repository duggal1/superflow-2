import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import SuperflowTextInsertion

/// Fixture command layers for Cmd+V resolution. Each closure maps a key code to
/// the single UTF-16 scalar it produces while Command is held, which is exactly
/// what UCKeyTranslate is asked for in production. No real layout is queried and
/// no key event is posted.
@MainActor
final class LayoutPasteKeyResolverTests: XCTestCase {
    func testQwertyResolvesAnsiV() {
        let code = LayoutPasteKeyResolver.resolveKeyCode { key in
            key == UInt16(kVK_ANSI_V) ? 0x76 : nil
        }
        XCTAssertEqual(code, CGKeyCode(kVK_ANSI_V))
    }

    /// "Dvorak - QWERTY ⌘" types `v` from key 47, but ⌘+47 is `.` there;
    /// the Command layer is the one that must be consulted (hex issue #162).
    func testCommandLayerIsUsedWhenItDiffersFromThePlainLayer() {
        let code = LayoutPasteKeyResolver.resolveKeyCode { key in
            switch key {
            case 9: return 0x76   // ⌘V
            case 47: return 0x2E  // plain "v" here is ⌘"."
            default: return nil
            }
        }
        XCTAssertEqual(code, 9)
    }

    /// A non-Latin active layout produces no ASCII letters on the plain layer,
    /// so the ASCII-capable command layer supplies the paste key (hex PR #81).
    func testAsciiCapableCommandLayerSuppliesTheKeyForNonLatinLayouts() {
        let code = LayoutPasteKeyResolver.resolveKeyCode { key in
            // Cyrillic wrap on the active layer; only key 9 yields ASCII "v".
            key == 9 ? 0x76 : nil
        }
        XCTAssertEqual(code, 9)
    }

    func testDuplicateMappingsKeepTheLowestKeyCode() {
        let code = LayoutPasteKeyResolver.resolveKeyCode { key in
            (key == 9 || key == 47) ? 0x56 : nil
        }
        XCTAssertEqual(code, 9)
    }

    func testNoMatchingKeyUsesTheExplicitFallback() {
        let code = LayoutPasteKeyResolver.resolveKeyCode(fallback: 77) { _ in nil }
        XCTAssertEqual(code, 77)
    }

    func testNonAsciiScalarsAreNeverMistakenForV() {
        let code = LayoutPasteKeyResolver.resolveKeyCode(fallback: 9) { key in
            key == 47 ? 0x0432 : nil // Cyrillic "в", not Latin "v"
        }
        XCTAssertEqual(code, 9)
    }
}
