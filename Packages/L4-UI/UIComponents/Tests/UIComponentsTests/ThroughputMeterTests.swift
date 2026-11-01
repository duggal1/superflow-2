import Foundation
import XCTest
@testable import SuperflowUIComponents

@MainActor
final class ThroughputMeterTests: XCTestCase {
    func testHistorySamplesOncePerSecondAndStaysBounded() {
        let meter = ThroughputMeter()
        let start = Date(timeIntervalSince1970: 100)
        meter.reset(now: start)
        meter.record(bytes: 0, at: start)
        meter.record(bytes: 1_000_000, at: start.addingTimeInterval(0.5))
        meter.tick(now: start.addingTimeInterval(0.5))
        XCTAssertTrue(meter.history.allSatisfy { $0 == 0 })
        meter.tick(now: start.addingTimeInterval(1))
        XCTAssertEqual(meter.history.count, 40)
        XCTAssertGreaterThan(meter.history.last ?? 0, 0)
    }
}
