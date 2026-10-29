import XCTest
@testable import SuperflowUIComponents

@MainActor
final class MenuMetricsTests: XCTestCase {
    func testOffsetsIncludeAirWithoutTurningItIntoAnItem() {
        let items = [MenuItem("Play") {}, MenuItem("Delete", gapBefore: true) {}]
        XCTAssertEqual(MenuMetrics.offsets(items), [4, 44])
        XCTAssertEqual(MenuMetrics.height(items), 80)
        XCTAssertEqual(MenuMetrics.index(at: 4, items), 0)
        XCTAssertNil(MenuMetrics.index(at: 36, items))
        XCTAssertEqual(MenuMetrics.index(at: 44, items), 1)
        XCTAssertNil(MenuMetrics.index(at: 76, items))
        XCTAssertEqual(MenuMetrics.height([]), 8)
    }

    func testPlacementUsesWindowOriginFlipsAndClamps() {
        let placement = MenuMetrics.placement(anchor: CGRect(x: 490, y: 480, width: 28, height: 28),
            size: CGSize(width: 220, height: 144), bounds: CGSize(width: 480, height: 500),
            origin: CGPoint(x: 40, y: 20))
        XCTAssertTrue(placement.flipped)
        XCTAssertEqual(placement.point, CGPoint(x: 252, y: 310))
        let top = MenuMetrics.placement(anchor: CGRect(x: 42, y: 30, width: 28, height: 28),
            size: CGSize(width: 220, height: 144), bounds: CGSize(width: 480, height: 500),
            origin: CGPoint(x: 40, y: 20))
        XCTAssertFalse(top.flipped)
        XCTAssertEqual(top.point, CGPoint(x: 8, y: 44))
    }

    func testKeyboardSkipsDisabledItemsAndDismissesBeforeRunning() {
        let host = MenuHost()
        var ran = false
        host.present(owner: UUID(), items: [MenuItem("Disabled", enabled: false) {},
            MenuItem("Enabled") { XCTAssertNil(host.presented); ran = true }], anchor: .zero)
        host.move(1)
        XCTAssertEqual(host.cursor, 1)
        host.move(1)
        XCTAssertEqual(host.cursor, 1)
        host.commit(0)
        XCTAssertFalse(ran)
        host.commit()
        XCTAssertTrue(ran)
    }
}
