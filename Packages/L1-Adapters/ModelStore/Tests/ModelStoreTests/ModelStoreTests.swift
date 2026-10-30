import CryptoKit
import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowModelStore

private actor FakeDownloader: ModelDownloading {
    let payload: Data
    private(set) var calls = 0

    init(payload: Data) { self.payload = payload }

    func download(from url: URL, to destination: URL, expectedBytes: Int64?,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        calls += 1
        progress(0.25)
        try payload.write(to: destination)
        progress(0.9)
    }
}

private actor FlakyDownloader: ModelDownloading {
    let payload: Data
    private(set) var destinations: [URL] = []
    private var calls = 0

    init(payload: Data) { self.payload = payload }

    func download(from url: URL, to destination: URL, expectedBytes: Int64?,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        calls += 1
        destinations.append(destination)
        if calls == 1 { throw URLError(.networkConnectionLost) }
        try payload.write(to: destination)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func record(_ value: Double) {
        lock.withLock { values.append(value) }
    }

    var all: [Double] { lock.withLock { values } }
}

final class ModelStoreTests: XCTestCase {
    func testBundledManifestPinsS1MiniArtifact() {
        let manifest = ModelManifest.load(root: URL(fileURLWithPath: "/nonexistent/superflow"), environment: [:])
        XCTAssertEqual(manifest.llm?.id, "s1-mini-q4-k-m")
        XCTAssertEqual(manifest.llm?.bytes, 484_219_808)
        XCTAssertEqual(manifest.llm?.sha256,
                       "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634")
    }

    private var root: URL!
    private let payload = Data((0..<4_096).map { UInt8($0 % 251) })

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-models-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var payloadSHA: String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private func artifact(id: String = "parakeet", sha: String? = nil,
                          bytes: Int64? = nil) -> ModelArtifact {
        ModelArtifact(id: id, fileName: "model.bin",
                      url: URL(string: "https://example.invalid/\(id).bin")!,
                      sha256: sha ?? payloadSHA,
                      bytes: bytes ?? Int64(payload.count))
    }

    func testEnsureDownloadsVerifiesAndCaches() async throws {
        let downloader = FakeDownloader(payload: payload)
        let manifest = ModelManifest(asr: ["parakeet": artifact()])
        let store = try ModelStore(root: root, manifest: manifest, downloader: downloader)
        let recorder = ProgressRecorder()

        let url = try await store.ensure(profileID: "parakeet") { recorder.record($0) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), payload)
        XCTAssertEqual(recorder.all.first, 0)
        XCTAssertEqual(recorder.all.last, 1)
        XCTAssertTrue(recorder.all.contains(0.25))

        let cached = await store.localURL(for: "parakeet")
        XCTAssertEqual(cached, url)
        _ = try await store.ensure(profileID: "parakeet") { _ in }
        let calls = await downloader.calls
        XCTAssertEqual(calls, 1)
    }

    func testMissingManifestEntryThrows() async throws {
        let downloader = FakeDownloader(payload: payload)
        let store = try ModelStore(root: root, manifest: .empty, downloader: downloader)
        do {
            _ = try await store.ensure(profileID: "missing") { _ in }
            XCTFail("expected modelUnavailable")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .modelUnavailable("No manifest entry for missing"))
        }
        let local = await store.localURL(for: "missing")
        XCTAssertNil(local)
        let calls = await downloader.calls
        XCTAssertEqual(calls, 0)
    }

    func testRetryUsesTheSameTemporaryFileSoChunksCanResume() async throws {
        let downloader = FlakyDownloader(payload: payload)
        let manifest = ModelManifest(asr: ["parakeet": artifact()])
        let store = try ModelStore(root: root, manifest: manifest, downloader: downloader)

        do {
            _ = try await store.ensure(profileID: "parakeet") { _ in }
            XCTFail("expected the first transfer to fail")
        } catch {}

        let url = try await store.ensure(profileID: "parakeet") { _ in }
        let destinations = await downloader.destinations
        XCTAssertEqual(destinations.count, 2)
        XCTAssertEqual(destinations.first, destinations.last,
                       "a retry must reuse the same temporary path or its chunks are orphaned")
        XCTAssertEqual(destinations.first?.lastPathComponent, ".download-model.bin.tmp")
        XCTAssertEqual(try Data(contentsOf: url), payload)
    }

    func testRepairDropsPartialChunksOfTheCorruptFile() async throws {
        let downloader = FakeDownloader(payload: payload)
        let manifest = ModelManifest(asr: ["parakeet": artifact()])
        let store = try ModelStore(root: root, manifest: manifest, downloader: downloader)
        let url = try await store.ensure(profileID: "parakeet") { _ in }

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".download-model.bin.tmp")
        let parts = SegmentedTransfer.partsDirectory(for: temporary)
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: parts.appendingPathComponent("part-0"))
        try Data("corrupt".utf8).write(to: url)

        _ = try await store.repair(profileID: "parakeet") { _ in }
        XCTAssertFalse(FileManager.default.fileExists(atPath: parts.path),
                       "resuming bad chunks would rebuild the same corrupt file")
        XCTAssertEqual(try Data(contentsOf: url), payload)
    }

    func testChecksumMismatchDoesNotInstall() async throws {
        let downloader = FakeDownloader(payload: payload)
        let wrong = String(repeating: "0", count: 64)
        let manifest = ModelManifest(asr: ["parakeet": artifact(sha: wrong)])
        let store = try ModelStore(root: root, manifest: manifest, downloader: downloader)
        do {
            _ = try await store.ensure(profileID: "parakeet") { _ in }
            XCTFail("expected checksum failure")
        } catch let error as SuperflowError {
            guard case .modelUnavailable(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("Checksum mismatch"))
        }
        let local = await store.localURL(for: "parakeet")
        XCTAssertNil(local)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        XCTAssertFalse(files.contains { $0.hasSuffix("model.bin") })
    }

    func testLLMDownload() async throws {
        let downloader = FakeDownloader(payload: payload)
        let llm = ModelArtifact(id: "s1-mini", fileName: "s1-mini.gguf",
                                url: URL(string: "https://example.invalid/s1.gguf")!,
                                sha256: payloadSHA, bytes: Int64(payload.count))
        let store = try ModelStore(root: root, manifest: ModelManifest(llm: llm), downloader: downloader)
        let url = try await store.ensureLLM { _ in }
        XCTAssertEqual(url.lastPathComponent, "s1-mini.gguf")
        let cached = await store.llmModelURL()
        XCTAssertEqual(cached, url)
    }

    func testRepairRedownloadsCorruptFile() async throws {
        let downloader = FakeDownloader(payload: payload)
        let manifest = ModelManifest(asr: ["parakeet": artifact()])
        let store = try ModelStore(root: root, manifest: manifest, downloader: downloader)
        let url = try await store.ensure(profileID: "parakeet") { _ in }
        try Data(repeating: 7, count: payload.count).write(to: url)

        let repaired = try await store.repair(profileID: "parakeet") { _ in }
        XCTAssertEqual(try Data(contentsOf: repaired), payload)
        let calls = await downloader.calls
        XCTAssertEqual(calls, 2)
    }

    func testLocalURLRejectsWrongSize() async throws {
        let downloader = FakeDownloader(payload: payload)
        let manifest = ModelManifest(asr: ["parakeet": artifact()])
        let store = try ModelStore(root: root, manifest: manifest, downloader: downloader)
        let url = try await store.ensure(profileID: "parakeet") { _ in }
        try Data(repeating: 1, count: 10).write(to: url)
        let local = await store.localURL(for: "parakeet")
        XCTAssertNil(local)
    }

    func testOverrideDirectoryWinsWithoutMarker() async throws {
        let override = root.appendingPathComponent("dev-models", isDirectory: true)
        let directory = override.appendingPathComponent("parakeet", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("model.bin")
        try payload.write(to: file)

        let store = try ModelStore(root: root, manifest: ModelManifest(asr: ["parakeet": artifact()]),
                                   downloader: FakeDownloader(payload: payload),
                                   environment: ["SUPERFLOW_MODEL_DIR": override.path])
        let local = await store.localURL(for: "parakeet")
        XCTAssertEqual(local, file)
    }

    func testManifestLoadsFromDisk() async throws {
        let artifact = artifact()
        let manifest = ModelManifest(asr: ["parakeet": artifact])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        let loaded = ModelManifest.load(root: root, environment: [:])
        XCTAssertEqual(loaded, manifest)
    }

    func testVerificationRejectsShortFile() throws {
        let file = root.appendingPathComponent("short.bin")
        try Data([1, 2, 3]).write(to: file)
        XCTAssertFalse(ModelVerification.matches(file: file, artifact: artifact()))
    }
}
