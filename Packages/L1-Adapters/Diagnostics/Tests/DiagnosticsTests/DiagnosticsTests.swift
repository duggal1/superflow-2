import Foundation
import XCTest
@testable import SuperflowDiagnostics

final class DiagnosticsTests: XCTestCase {
    func testMetricsRingDropsOldestAtCapacity() {
        let ring = MetricsRing(capacity: 3)
        for i in 0..<5 { ring.record("stage", valueMs: Double(i)) }
        let values = ring.snapshot.metrics.map(\.valueMs)
        XCTAssertEqual(values, [2, 3, 4])
    }

    func testEventsAreBoundedAndKeepFields() {
        let ring = MetricsRing(capacity: 2)
        ring.event("first", ["a": "1"])
        ring.event("second", ["b": "2"])
        ring.event("third", ["c": "3"])
        let events = ring.snapshot.events
        XCTAssertEqual(events.map(\.name), ["second", "third"])
        XCTAssertEqual(events.last?.fields, ["c": "3"])
    }

    func testResetClearsBothBuffers() {
        let ring = MetricsRing()
        ring.record("x", valueMs: 1)
        ring.event("y", [:])
        ring.reset()
        XCTAssertTrue(ring.snapshot.metrics.isEmpty)
        XCTAssertTrue(ring.snapshot.events.isEmpty)
    }

    func testSignpostIntervalStateIsReturnedAndAcceptedByEnd() {
        let logger = DiagnosticsLogger(category: "tests")
        let state = logger.begin("contract.interval")
        logger.end("contract.interval", state: state)
    }

    func testExportWritesDecodableBundleWithoutTranscripts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-diag-\(UUID().uuidString)", isDirectory: true)
        let database = directory.appendingPathComponent("Superflow.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_024).write(to: database)
        let ring = MetricsRing()
        ring.record("stop_to_final", valueMs: 420)
        ring.event("session_started", ["kind": "dictation"])
        let exporter = DiagnosticsExporter(metrics: ring, databaseURL: database)
        let output = directory.appendingPathComponent("diagnostics.json")

        try await exporter.exportDiagnostics(to: output)
        let data = try Data(contentsOf: output)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DiagnosticsPayload.self, from: data)
        XCTAssertEqual(payload.metrics.count, 1)
        XCTAssertEqual(payload.metrics.first?.name, "stop_to_final")
        XCTAssertEqual(payload.events.first?.fields["kind"], "dictation")
        XCTAssertEqual(payload.databaseBytes, 1_024)
        XCTAssertFalse(payload.notes.isEmpty)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("transcript"))
        XCTAssertFalse(text.lowercased().contains("audio samples"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testExportWithoutDatabaseLeavesBytesNil() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-diag-\(UUID().uuidString)", isDirectory: true)
        let output = directory.appendingPathComponent("nested/diagnostics.json")
        let exporter = DiagnosticsExporter(metrics: MetricsRing())
        try await exporter.exportDiagnostics(to: output)
        let data = try Data(contentsOf: output)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DiagnosticsPayload.self, from: data)
        XCTAssertNil(payload.databaseBytes)
        XCTAssertEqual(payload.architecture.isEmpty, false)
        try? FileManager.default.removeItem(at: directory)
    }
}
