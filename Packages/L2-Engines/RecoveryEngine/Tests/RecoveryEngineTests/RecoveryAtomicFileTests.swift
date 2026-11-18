import XCTest
@testable import SuperflowRecoveryEngine

final class RecoveryAtomicFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = RecoveryTestSupport.tempRoot("atomic")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A crash at each of the six write stages must leave either the complete old file or the
    /// complete new file, never a partial one. A fresh store instance simulates the restart.
    func testEveryCrashStageLeavesCompleteOldOrNewFile() throws {
        let old = Data("OLD-\(String(repeating: "a", count: 4_096))".utf8)
        let new = Data("NEW-\(String(repeating: "b", count: 9_999))".utf8)
        for stage in AtomicWriteStage.allCases {
            let directory = root.appendingPathComponent(stage.rawValue, isDirectory: true)
            let store = AtomicFileStore(root: directory)
            try store.write(old, named: "value.bin")
            if stage == .committed {
                // The control stage: the write completes, no crash is injected.
                try store.write(new, named: "value.bin", crashAt: stage)
            } else {
                XCTAssertThrowsError(try store.write(new, named: "value.bin", crashAt: stage),
                                     "\(stage) must simulate termination") { error in
                    XCTAssertEqual(error as? RecoveryStorageError, .injectedCrash(stage))
                }
            }
            let restarted = AtomicFileStore(root: directory)
            let actual = try XCTUnwrap(try restarted.read("value.bin"), "\(stage): file vanished")
            switch stage {
            case .prepare, .tempWrite, .tempSync:
                XCTAssertEqual(actual, old, "\(stage): old value must survive intact")
            case .replace, .directorySync, .committed:
                XCTAssertEqual(actual, new, "\(stage): new value must be complete")
            }
            let temps = try restarted.quarantineTemps()
            XCTAssertEqual(temps.count, (stage == .tempWrite || stage == .tempSync) ? 1 : 0,
                           "\(stage): only torn temp files should be quarantined")
            XCTAssertEqual(try restarted.read("value.bin"), actual)
            try restarted.write(Data("FINAL".utf8), named: "value.bin")
            XCTAssertEqual(try restarted.read("value.bin"), Data("FINAL".utf8))
        }
    }

    func testUnicodeAndVeryLongPayloadsRoundTripByteForByte() throws {
        let text = String(repeating: "日本語🎙️é\n", count: 12_000) + "\"quoted\" \\ \\u0000 ✅"
        let data = Data(text.utf8)
        let store = AtomicFileStore(root: root.appendingPathComponent("unicode"))
        try store.write(data, named: "text.bin")
        XCTAssertEqual(try store.read("text.bin"), data)
        XCTAssertGreaterThan(data.count, 100_000)
    }

    func testConcurrentWritersNeverProduceTornFile() async throws {
        let store = AtomicFileStore(root: root.appendingPathComponent("concurrent"))
        let payloads: [Data] = (0..<16).map { i in
            Data("writer-\(i)-\(String(repeating: "x", count: 70_000))".utf8)
        }
        await withTaskGroup(of: Void.self) { group in
            for payload in payloads {
                group.addTask {
                    _ = try? store.write(payload, named: "value.bin")
                }
            }
        }
        let result = try XCTUnwrap(try store.read("value.bin"))
        XCTAssertTrue(payloads.contains(result), "final file must be exactly one complete payload")
        XCTAssertTrue(try store.quarantineTemps().allSatisfy { $0.path.contains("Quarantine") })
    }

    func testFilesystemFailurePropagatesWithoutCreatingPhantomFile() throws {
        let blocked = root.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocked)
        let store = AtomicFileStore(root: blocked.appendingPathComponent("child"))
        XCTAssertThrowsError(try store.write(Data("x".utf8), named: "value.bin"))
        XCTAssertEqual(try? Data(contentsOf: blocked), Data("not a directory".utf8))
    }

    func testChecksumDetectsSingleByteChange() {
        let data = Data("a checksummed payload".utf8)
        let expected = RecoveryChecksum.fnv1a(data)
        var changed = data
        changed[0] ^= 0x01
        XCTAssertNotEqual(RecoveryChecksum.fnv1a(changed), expected)
        XCTAssertEqual(RecoveryChecksum.fnv1a(data), expected)
    }
}
