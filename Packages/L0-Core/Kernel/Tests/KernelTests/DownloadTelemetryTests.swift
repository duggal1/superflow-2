import Foundation
import SuperflowKernel
import XCTest

final class DownloadTelemetryTests: XCTestCase {
    func testSnapshotIsNilUntilATransferStarts() {
        let meter = DownloadTelemetry()
        XCTAssertNil(meter.snapshot())
    }

    func testRecordsBytesAndEnds() {
        let meter = DownloadTelemetry()
        meter.begin(label: "parakeet", totalBytes: 1_000_000)
        meter.record(receivedBytes: 250_000)
        let snapshot = meter.snapshot()
        XCTAssertEqual(snapshot?.label, "parakeet")
        XCTAssertEqual(snapshot?.receivedBytes, 250_000)
        XCTAssertEqual(snapshot?.totalBytes, 1_000_000)
        XCTAssertEqual(snapshot?.fraction, 0.25)
        meter.end()
        XCTAssertNil(meter.snapshot())
    }

    func testTotalCanArriveAfterTheFirstByte() {
        let meter = DownloadTelemetry()
        meter.begin(label: "s1-mini")
        meter.record(receivedBytes: 1_000_000)
        XCTAssertNil(meter.snapshot()?.fraction)
        meter.expect(totalBytes: 4_000_000)
        XCTAssertEqual(meter.snapshot()?.fraction, 0.25)
        meter.end()
    }

    func testRateIsMeasuredFromBytesOverTime() async throws {
        let meter = DownloadTelemetry()
        meter.begin(label: "throughput", totalBytes: 10_000_000)
        meter.record(receivedBytes: 0)
        try await Task.sleep(for: .milliseconds(320))
        meter.record(receivedBytes: 1_000_000)
        let rate = try XCTUnwrap(meter.snapshot()?.bytesPerSecond)
        // One mebibyte in roughly a third of a second: a few MB/s at least, and
        // nowhere near an invented constant.
        XCTAssertGreaterThan(rate, 1_000_000)
        XCTAssertLessThan(rate, 20_000_000)
        meter.end()
    }

    func testStartingANewTransferDiscardsThePreviousReading() {
        let meter = DownloadTelemetry()
        meter.begin(label: "first", totalBytes: 100)
        meter.record(receivedBytes: 100)
        meter.begin(label: "second", totalBytes: 200)
        let snapshot = meter.snapshot()
        XCTAssertEqual(snapshot?.label, "second")
        XCTAssertEqual(snapshot?.receivedBytes, 0)
        XCTAssertEqual(snapshot?.totalBytes, 200)
        meter.end()
    }
}
