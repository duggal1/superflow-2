import CoreGraphics
import SwiftUI
import XCTest
@testable import SuperflowFeatureIsland

final class NotchShapeTests: XCTestCase {
    func testZeroRadiiDrawARectangle() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let path = NotchShape(top: 0, bottom: 0).path(in: rect)
        XCTAssertEqual(path.boundingRect.origin.x, rect.minX, accuracy: 0.0001)
        XCTAssertEqual(path.boundingRect.origin.y, rect.minY, accuracy: 0.0001)
        XCTAssertEqual(path.boundingRect.size.width, rect.width, accuracy: 0.0001)
        XCTAssertEqual(path.boundingRect.size.height, rect.height, accuracy: 0.0001)
    }

    func testPathStaysInsideTheRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        for (top, bottom) in [(6.0, 14.0), (12.0, 24.0), (0.0, 12.0)] {
            let bounds = NotchShape(top: top, bottom: bottom).path(in: rect).boundingRect
            XCTAssertTrue(rect.insetBy(dx: -0.0001, dy: -0.0001).contains(bounds),
                          "top \(top) bottom \(bottom)")
        }
    }

    func testRadiiClampInsteadOfCrashing() {
        let path = NotchShape(top: 500, bottom: 500).path(in: CGRect(x: 0, y: 0, width: 40, height: 20))
        XCTAssertFalse(path.isEmpty)
    }

    func testAnimatableDataRoundTrips() {
        var shape = NotchShape(top: 6, bottom: 14)
        shape.animatableData = .init(12, 24)
        XCTAssertEqual(shape.top, 12)
        XCTAssertEqual(shape.bottom, 24)
        XCTAssertEqual(shape.animatableData.first, 12)
        XCTAssertEqual(shape.animatableData.second, 24)
    }

    func testFlatTopStartsAtTheTopEdge() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let path = NotchShape(top: 6, bottom: 14).path(in: rect)
        XCTAssertEqual(path.boundingRect.minY, 0, accuracy: 0.0001)
    }
}
