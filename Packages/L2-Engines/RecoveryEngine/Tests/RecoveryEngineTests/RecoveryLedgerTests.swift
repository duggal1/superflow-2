import XCTest
@testable import SuperflowRecoveryEngine

final class RecoveryLedgerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws { root = RecoveryTestSupport.tempRoot("ledger") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func record(_ id: String, kind: RecoveryLedgerKind = .started,
                        detail: String? = nil) -> RecoveryLedgerRecord {
        RecoveryLedgerRecord(id: id, kind: kind, session: "session-\(id)", detail: detail)
    }

    func testVersionedChecksummedRecordRoundTrips() async throws {
        let ledger = RecoveryLedger(root: root)
        let first = try await ledger.append(record("one", detail: "日本語 🎙️"))
        let second = try await ledger.append(record("two", kind: .finalized))
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        let read = try await ledger.read()
        XCTAssertEqual(read.records.count, 2)
        XCTAssertEqual(read.records.map(\.sequence), [1, 2])
        XCTAssertEqual(read.records.first?.detail, "日本語 🎙️")
        XCTAssertTrue(read.integrity.isClean)
    }

    /// Each atomic stage is a distinct crash point: the log either did not gain the record or it
    /// gained the whole record. There is no state in between.
    func testCrashAtEveryWriteStageKeepsLogConsistent() async throws {
        for stage in AtomicWriteStage.allCases {
            let ledger = RecoveryLedger(root: root.appendingPathComponent(stage.rawValue))
            try await ledger.append(record("\(stage)-first"))
            if stage == .committed {
                try await ledger.append(record("\(stage)-second"), crashAt: stage)
            } else {
                do {
                    try await ledger.append(record("\(stage)-second"), crashAt: stage)
                    XCTFail("\(stage): expected simulated termination")
                } catch let error as RecoveryStorageError {
                    XCTAssertEqual(error, .injectedCrash(stage))
                }
            }
            let read = try await ledger.read()
            let expected = (stage == .prepare || stage == .tempWrite || stage == .tempSync) ? 1 : 2
            XCTAssertEqual(read.records.count, expected, "\(stage): wrong visible record count")
            XCTAssertTrue(read.integrity.isClean, "\(stage): a torn temp file must not corrupt the log")
            let quarantined = try await ledger.quarantineDamaged()
            XCTAssertTrue(quarantined.isEmpty)
        }
    }

    func testTruncatedCorruptAndVersionSkewedRecordsAreReportedAndQuarantined() async throws {
        let ledger = RecoveryLedger(root: root)
        for id in ["keep-1", "keep-2", "bad-1", "bad-2", "bad-3"] {
            try await ledger.append(record(id))
        }
        let recordsDir = root.appendingPathComponent("Records", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: recordsDir, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 5)

        // Truncated frame, flipped payload byte, and an unknown format version.
        let truncated = files[2]
        var data = try Data(contentsOf: truncated)
        try data.subdata(in: 0..<(data.count / 2)).write(to: truncated)

        let corrupt = files[3]
        data = try Data(contentsOf: corrupt)
        data[data.count - 1] ^= 0x7F
        try data.write(to: corrupt)

        let skewed = files[4]
        data = try Data(contentsOf: skewed)
        var version: UInt16 = 99
        withUnsafeBytes(of: &version) { data.replaceSubrange(4..<6, with: $0) }
        try data.write(to: skewed)

        let read = try await ledger.read()
        XCTAssertEqual(read.records.count, 2)
        XCTAssertEqual(read.integrity.truncated, 1)
        XCTAssertEqual(read.integrity.corrupt, 1)
        XCTAssertEqual(read.integrity.versionMismatch, 1)
        XCTAssertFalse(read.integrity.isClean)

        let moved = try await ledger.quarantineDamaged()
        XCTAssertEqual(moved.count, 3)
        let after = try await ledger.read()
        XCTAssertEqual(after.records.count, 2, "valid history must survive quarantine")
        XCTAssertTrue(after.integrity.isClean)
    }

    func testReplayIsIdempotentAcrossRepeatedCallsAndRestarts() async throws {
        actor Sink {
            var ids: [String] = []
            func add(_ id: String) { ids.append(id) }
        }
        let sink = Sink()
        let ledger = RecoveryLedger(root: root)
        try await ledger.append(record("alpha"))
        try await ledger.append(record("beta", kind: .finalized))
        _ = try await ledger.replay { entry in await sink.add(entry.id) }
        _ = try await ledger.replay { entry in await sink.add(entry.id) }
        let sameProcess = await sink.ids
        XCTAssertEqual(sameProcess.count, 2, "a second replay in one process is a no-op")
        XCTAssertEqual(Set(sameProcess), Set(["alpha", "beta"]))

        // A fresh process has no in-memory applied set. Idempotency there comes from the engine's
        // deterministic record ids and its segment-level dedupe, not from this in-memory marker.
        let restarted = RecoveryLedger(root: root)
        _ = try await restarted.replay { entry in await sink.add(entry.id) }
        let ids = await sink.ids
        XCTAssertEqual(ids.count, 4)
        let freshCount = await restarted.appliedCount
        XCTAssertEqual(freshCount, 2)
    }

    func testManyConcurrentSessionsAndLongUnicodeNotes() async throws {
        let ledger = RecoveryLedger(root: root)
        let long = String(repeating: "🚀つよし y", count: 4_000)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<120 {
                group.addTask {
                    _ = try? await ledger.append(
                        RecoveryLedgerRecord(id: "session-\(i)-watermark", kind: .watermark,
                                             session: "session-\(i)", source: "mic",
                                             samplePosition: Int64(i * 1_600), detail: long))
                }
            }
        }
        let read = try await ledger.read()
        XCTAssertEqual(read.records.count, 120)
        XCTAssertEqual(Set(read.records.map(\.sequence)), Set(1...120), "sequences must be unique")
        XCTAssertTrue(read.records.allSatisfy { $0.detail == long })
        XCTAssertEqual(read.integrity.valid, 120)
    }
}
