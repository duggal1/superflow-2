import FluidAudio
import Foundation
import SuperflowKernel
import XCTest
@testable import SuperflowASRFluidAudio

/// Records download calls and materializes the profile's artifact tree on disk so the real
/// integrity verification runs against what the fake "downloaded".
/// Thread-safe progress recorder; the download callbacks fire on other executors.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    func record(_ value: Double) { lock.withLock { storage.append(value) } }
    var values: [Double] { lock.withLock { storage } }
}

actor RecordingDownloader: FluidAudioModelDownloading {
    private(set) var calls: [String] = []
    private var failNext = false
    private var leaveIncomplete = false

    func failOnce() { failNext = true }
    func leaveCacheIncomplete() { leaveIncomplete = true }

    func download(profileID: String, cacheRoot: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        calls.append(profileID)
        if failNext {
            failNext = false
            throw SuperflowError.storage("injected download failure")
        }
        guard let profile = FluidAudioCatalog.profile(for: profileID) else {
            throw SuperflowError.modelUnavailable("unknown profile")
        }
        progress(0)
        let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: cacheRoot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let artifacts = leaveIncomplete
            ? Array(profile.requiredArtifacts.dropLast())
            : profile.requiredArtifacts
        for artifact in artifacts {
            let url = directory.appendingPathComponent(artifact)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(artifact.utf8).write(to: url)
        }
        progress(1)
    }
}

final class FluidAudioModelDownloaderTests: XCTestCase {
    private func emptyRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("asr-dl-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func testPrepareDownloadsVerifiesAndLoadsOnCleanInstall() async throws {
        let root = emptyRoot()
        let downloader = RecordingDownloader()
        let spy = EngineSpy()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: root,
            engineFactory: { _, _ in try await spy.make() },
            voiceActivityFactory: { FakeVoiceActivity() },
            downloader: downloader)

        let availableBefore = await recognizer.isAvailable(profileID: ModelProfile.parakeetEOU120M.id)
        XCTAssertFalse(availableBefore, "a clean install has no ASR artifacts")

        let progress = ProgressBox()
        try await recognizer.prepare(profileID: ModelProfile.parakeetEOU120M.id) { progress.record($0) }

        let calls = await downloader.calls
        XCTAssertEqual(calls, [ModelProfile.parakeetEOU120M.id])
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertEqual(progress.values.first, 0)
        let availableAfter = await recognizer.isAvailable(profileID: ModelProfile.parakeetEOU120M.id)
        XCTAssertTrue(availableAfter)
        let ready = await recognizer.isReady
        XCTAssertTrue(ready, "prepare must leave the recognizer ready to make streams")
    }

    func testPrepareReusesVerifiedCacheWithoutDownloading() async throws {
        let root = try makeModelCache(profileID: ModelProfile.parakeetEOU120M.id)
        let downloader = RecordingDownloader()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: root,
            engineFactory: { _, _ in FakeEngine() },
            downloader: downloader)

        try await recognizer.prepare(profileID: ModelProfile.parakeetEOU120M.id) { _ in }
        let calls = await downloader.calls
        XCTAssertTrue(calls.isEmpty, "an intact cache must not hit the network")
    }

    func testPrepareRefetchesCorruptCacheInsteadOfLoadingIt() async throws {
        let root = try makeModelCache(profileID: ModelProfile.parakeetEOU120M.id)
        let profile = try XCTUnwrap(FluidAudioCatalog.profile(for: ModelProfile.parakeetEOU120M.id))
        XCTAssertTrue(try FluidAudioArtifactIntegrity.verify(profile: profile, cacheRoot: root))

        // Tamper with a byte in a required artifact: the sidecar no longer matches.
        let directory = FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: root)
        let artifact = directory.appendingPathComponent(profile.requiredArtifacts[0])
        try Data("garbage".utf8).write(to: artifact)
        XCTAssertFalse(try FluidAudioArtifactIntegrity.verify(profile: profile, cacheRoot: root))

        let downloader = RecordingDownloader()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: root,
            engineFactory: { _, _ in FakeEngine() },
            downloader: downloader)
        try await recognizer.prepare(profileID: ModelProfile.parakeetEOU120M.id) { _ in }

        let calls = await downloader.calls
        XCTAssertEqual(calls, [ModelProfile.parakeetEOU120M.id],
                       "a cache that fails verification must be refetched")
        XCTAssertTrue(try FluidAudioArtifactIntegrity.verify(profile: profile, cacheRoot: root))
    }

    func testPrepareFailsWhenDownloadLeavesCacheIncomplete() async throws {
        let root = emptyRoot()
        let downloader = RecordingDownloader()
        await downloader.leaveCacheIncomplete()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: root,
            engineFactory: { _, _ in throw SuperflowError.modelUnavailable("must not load") },
            downloader: downloader)

        do {
            try await recognizer.prepare(profileID: ModelProfile.parakeetEOU120M.id) { _ in }
            XCTFail("expected modelUnavailable")
        } catch let error as SuperflowError {
            guard case .modelUnavailable(let message) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(message.contains("integrity"), message)
        }
    }

    func testPreparePropagatesDownloadFailure() async throws {
        let root = emptyRoot()
        let downloader = RecordingDownloader()
        await downloader.failOnce()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: root, engineFactory: { _, _ in FakeEngine() },
            downloader: downloader)

        do {
            try await recognizer.prepare(profileID: ModelProfile.parakeetEOU120M.id) { _ in }
            XCTFail("expected the download failure to propagate")
        } catch let error as SuperflowError {
            XCTAssertEqual(error, .storage("injected download failure"))
        }
    }

    func testWarmUpNeverDownloadsOnAMissingCache() async throws {
        let root = emptyRoot()
        let downloader = RecordingDownloader()
        let recognizer = FluidAudioRecognizer(
            modelCacheRoot: root, engineFactory: { _, _ in try await FakeEngine() },
            downloader: downloader)

        do {
            try await recognizer.warmUp(profile: ModelProfile.parakeetEOU120M.id)
            XCTFail("expected modelUnavailable")
        } catch let error as SuperflowError {
            guard case .modelUnavailable = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
        let calls = await downloader.calls
        XCTAssertTrue(calls.isEmpty, "record-time warm-up must stay offline")
    }

    func testDigestIsStableAcrossRepeatedComputations() throws {
        let root = try makeModelCache(profileID: ModelProfile.parakeetEOU120M.id)
        let profile = try XCTUnwrap(FluidAudioCatalog.profile(for: ModelProfile.parakeetEOU120M.id))
        let first = try FluidAudioArtifactIntegrity.digest(profile: profile, cacheRoot: root)
        let second = try FluidAudioArtifactIntegrity.digest(profile: profile, cacheRoot: root)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    /// The multilingual tier is downloaded by subdirectory, and FluidAudio saves it under
    /// whatever directory it is handed. That directory must be the repo folder in
    /// `FluidAudioCatalog.modelDirectory`, or the finished download never verifies.
    func testFlatMultilingualCacheMovesUnderTheRepoFolder() throws {
        let root = emptyRoot()
        let subdirectory = "latin/2240ms"
        let legacy = root.appendingPathComponent(subdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let weight = legacy.appendingPathComponent("encoder.mlmodelc")
        try Data("weights".utf8).write(to: weight)

        let repoDirectory = root.appendingPathComponent(Repo.nemotronMultilingual.folderName,
                                                        isDirectory: true)
        FluidAudioModelHubDownloader.adoptFlatCacheIfNeeded(
            cacheRoot: root, subdirectory: subdirectory, repoDirectory: repoDirectory)

        let moved = repoDirectory.appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent("encoder.mlmodelc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: weight.path))
    }

    /// The catalog, not the downloader, owns the destination. Assert they agree so a
    /// change to one side cannot silently strand the other.
    func testMultilingualDownloadDirectoryIsTheCatalogDirectory() throws {
        let root = emptyRoot()
        let profile = try XCTUnwrap(FluidAudioCatalog.profile(
            for: ModelProfile.nemotron35Streaming.id))
        let expected = root
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
            .appendingPathComponent("latin/2240ms", isDirectory: true)
        XCTAssertEqual(FluidAudioCatalog.modelDirectory(for: profile, cacheRoot: root).path,
                       expected.path)
    }

    func testInvalidateRemovesCacheAndMarker() throws {
        let root = try makeModelCache(profileID: ModelProfile.parakeetEOU120M.id)
        let profile = try XCTUnwrap(FluidAudioCatalog.profile(for: ModelProfile.parakeetEOU120M.id))
        XCTAssertTrue(try FluidAudioArtifactIntegrity.verify(profile: profile, cacheRoot: root))
        FluidAudioArtifactIntegrity.invalidate(profile: profile, cacheRoot: root)
        XCTAssertFalse(try FluidAudioArtifactIntegrity.verify(profile: profile, cacheRoot: root))
        XCTAssertFalse(FluidAudioCatalog.isInstalled(profile.id, cacheRoot: root))
    }
}
