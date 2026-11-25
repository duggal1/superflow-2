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

    // MARK: - Sanitization: user content is never retained

    func testSanitizerKeepsIdentifiersAndHashesProse() {
        XCTAssertEqual(DiagnosticSanitizer.token("session.stop.ms"), "session.stop.ms")
        XCTAssertEqual(DiagnosticSanitizer.token("session stop ms").hasPrefix("h"), true)
        XCTAssertFalse(DiagnosticSanitizer.token("/Users/me/secret").contains("Users"))
        XCTAssertEqual(DiagnosticSanitizer.token(""), "unspecified")
        XCTAssertEqual(DiagnosticSanitizer.bounded("abcdef", limit: 3), "abc")
        XCTAssertEqual(DiagnosticSanitizer.finite(.nan), 0)
        XCTAssertEqual(DiagnosticSanitizer.finite(.infinity), 0)
    }

    func testEventFieldsNeverCarryUserProseOrUnboundedFieldCounts() {
        let ring = MetricsRing(capacity: 8)
        var many: [String: String] = [:]
        for i in 0..<40 { many["field.\(i)"] = "value.\(i)" }
        ring.event("bulk", many)
        ring.event("session.cleanup", ["transcript": "The budget meeting starts at nine tomorrow"])

        let events = ring.snapshot.events
        XCTAssertLessThanOrEqual(events[0].fields.count, DiagnosticSanitizer.maxFields)
        XCTAssertGreaterThan(events[0].sequence, 0)

        let value = events[1].fields["transcript"]
        XCTAssertNotNil(value)
        XCTAssertEqual(value?.contains(" "), false)
        XCTAssertEqual(value?.hasPrefix("h"), true)
        XCTAssertFalse(events[1].fields.values.contains { $0.contains("budget") })
    }

    func testExportedPayloadContainsNoUserContent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-diag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let ring = MetricsRing(capacity: 32)
        ring.record("asr.latency", valueMs: 12, device: "Harshit's MacBook Pro Microphone")
        ring.event("session.finalize", ["transcript": "Project Phoenix ships on Friday"])
        ring.counters.noteAudioDiscontinuity()
        ring.counters.noteDeadlineMiss()
        ring.counters.observeQueueAgeMs(41.5)
        ring.counters.setModelRevision("/Users/harshit/Models/phoenix-v3")

        let exporter = DiagnosticsExporter(metrics: ring)
        let output = directory.appendingPathComponent("diagnostics.json")
        try await exporter.exportDiagnostics(to: output)

        let data = try Data(contentsOf: output)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("Project Phoenix ships on Friday"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("harshit"))
        XCTAssertFalse(text.contains("MacBook"))
        XCTAssertFalse(text.contains("Phoenix"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DiagnosticsPayload.self, from: data)
        XCTAssertEqual(payload.metrics.count, 1)
        XCTAssertEqual(payload.events.count, 1)
        XCTAssertEqual(payload.counters.audioDiscontinuities, 1)
        XCTAssertEqual(payload.counters.deadlineMisses, 1)
        XCTAssertEqual(payload.counters.maxQueueAgeMs, 41.5)
        XCTAssertEqual(payload.counters.modelRevision.hasPrefix("h"), true)
        XCTAssertEqual(payload.counters.modelRevisionChanges, 1)
        XCTAssertEqual(payload.timing.count, 1)
        XCTAssertEqual(payload.timing.first?.device.hasPrefix("h"), true)
        XCTAssertEqual(payload.notes, [DiagnosticsExporter.notice])
    }

    // MARK: - Bounded memory and counters

    func testCountersAreFixedSizeAndNeverTrap() {
        let counters = DiagnosticsCounters()
        for _ in 0..<10_000 {
            counters.noteRingOverflow()
            counters.noteAudioDiscontinuity()
            counters.noteDeadlineMiss()
            counters.observeQueueAgeMs(.nan)
        }
        let snapshot = counters.snapshot
        XCTAssertEqual(snapshot.ringOverflows, 10_000)
        XCTAssertEqual(snapshot.audioDiscontinuities, 10_000)
        XCTAssertEqual(snapshot.deadlineMisses, 10_000)
        XCTAssertEqual(snapshot.maxQueueAgeMs, 0)
        XCTAssertEqual(snapshot.modelRevision, "unspecified")
        XCTAssertEqual(CounterSnapshot().modelRevision, "unspecified")
    }

    func testIncrementalEventReaderAdvancesBySequence() {
        let ring = MetricsRing(capacity: 10)
        ring.event("a", [:])
        ring.event("b", [:])
        ring.event("c", [:])

        let first = ring.events(after: 0, limit: 2)
        XCTAssertEqual(first.map(\.name), ["a", "b"])
        let next = ring.events(after: first.last!.sequence, limit: 10)
        XCTAssertEqual(next.map(\.name), ["c"])
        XCTAssertTrue(ring.events(after: 999, limit: 10).isEmpty)
    }

    func testRingOverflowCounterTracksDroppedSamples() {
        let counters = DiagnosticsCounters()
        let ring = MetricsRing(capacity: 2, counters: counters)
        for i in 0..<5 { ring.record("stage", valueMs: Double(i)) }
        XCTAssertEqual(counters.snapshot.ringOverflows, 3)
        XCTAssertEqual(ring.snapshot.metrics.map(\.valueMs), [3, 4])
        XCTAssertEqual(ring.snapshot.metrics.count, 2)
    }

    func testTimingSummaryPercentilesAreCorrectAndBounded() {
        let ring = MetricsRing(capacity: 500)
        for i in 1...100 { ring.record("asr.ms", valueMs: Double(i), device: "device.a") }
        for i in 1...10 { ring.record("vad.ms", valueMs: Double(i), device: "device.b") }
        ring.record("bad.ms", valueMs: .nan, device: "device.a")

        let summary = TimingSummaryBuilder.build(from: ring.snapshot.metrics)
        XCTAssertEqual(summary.count, 2)
        let asr = summary[0]
        XCTAssertEqual(asr.device, "device.a")
        XCTAssertEqual(asr.metric, "asr.ms")
        XCTAssertEqual(asr.count, 100)
        XCTAssertEqual(asr.minMs, 1)
        XCTAssertEqual(asr.p50Ms, 50)
        XCTAssertEqual(asr.p95Ms, 95)
        XCTAssertEqual(asr.p99Ms, 99)
        XCTAssertEqual(asr.maxMs, 100)

        let many = (0..<100).map { MetricSample(name: "m.\($0)", valueMs: 1, device: "d") }
        XCTAssertLessThanOrEqual(TimingSummaryBuilder.build(from: many).count,
                                 TimingSummaryBuilder.maxGroups)
    }

    // MARK: - Fail-open signposts

    private enum TestError: Error { case expected }

    func testModuleLoggersAndMeasureClosesIntervalOnThrow() {
        for module in DiagnosticsModule.allCases {
            let logger = DiagnosticsLoggers.logger(for: module)
            XCTAssertEqual(logger.measure("test.stage") { 42 }, 42)
            XCTAssertThrowsError(try logger.measure("test.throwing") { () -> Int in
                throw TestError.expected
            })
        }
    }
}
