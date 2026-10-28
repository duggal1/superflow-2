import CoreGraphics
import XCTest
@testable import SuperflowFeatureIsland

final class NotchGeometryTests: XCTestCase {
    func testFourteenInchNotch() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(frame: frame, safeTop: 32,
                                     leftWidth: 620, rightWidth: 620, scale: 2)
        XCTAssertTrue(geometry.hasNotch)
        XCTAssertEqual(geometry.notch.width, 272)
        XCTAssertEqual(geometry.notch.height, 32)
        XCTAssertEqual(geometry.band, 32)
        XCTAssertEqual(geometry.centerX, 756)
    }

    func testSixteenInchOnANonZeroOrigin() {
        let frame = CGRect(x: 1920, y: -120, width: 1728, height: 1117)
        let geometry = NotchGeometry(frame: frame, safeTop: 38,
                                     leftWidth: 760, rightWidth: 760, scale: 2)
        XCTAssertTrue(geometry.hasNotch)
        XCTAssertEqual(geometry.notch.width, 208)
        XCTAssertEqual(geometry.band, 38)
        XCTAssertEqual(geometry.centerX, 1920 + 760 + 104)
        XCTAssertEqual(geometry.centerX * 2, (geometry.centerX * 2).rounded())
    }

    func testDisplayWithoutANotch() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry(frame: frame, safeTop: 0,
                                     leftWidth: nil, rightWidth: nil, scale: 2)
        XCTAssertFalse(geometry.hasNotch)
        XCTAssertEqual(geometry.notch, .zero)
        XCTAssertEqual(geometry.band, NotchGeometry.fallbackBand)
        XCTAssertEqual(geometry.centerX, 1280)
    }

    func testCenterIsSnappedToADevicePixel() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // 1512 - 619.5 - 620 = 272.5 wide, so the centre lands between pixels.
        let one = NotchGeometry(frame: frame, safeTop: 32,
                                leftWidth: 619.5, rightWidth: 620, scale: 2)
        XCTAssertEqual(one.centerX * 2, (one.centerX * 2).rounded(), accuracy: 0.0001)

        let two = NotchGeometry(frame: frame, safeTop: 32,
                                leftWidth: 619.5, rightWidth: 620, scale: 1)
        XCTAssertEqual(two.centerX, two.centerX.rounded(), accuracy: 0.0001)
    }

    func testAuxAreasThatDoNotDescribeANotchFallBack() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(frame: frame, safeTop: 32,
                                     leftWidth: 1200, rightWidth: 1200, scale: 2)
        XCTAssertFalse(geometry.hasNotch)
        XCTAssertEqual(geometry.band, NotchGeometry.fallbackBand)
    }
}
