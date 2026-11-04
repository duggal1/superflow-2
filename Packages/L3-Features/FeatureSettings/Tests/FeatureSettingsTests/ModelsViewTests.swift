import SuperflowFeatureSettings
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import SuperflowUIComponents
import XCTest

/// Stands in for the recognizer: the port onboarding and Settings install the
/// speech model through. Its artifacts are not `ModelStore`'s.
private actor InstalledASRProvider: ASRModelProvider {
    private let installed: Bool
    init(installed: Bool) { self.installed = installed }
    func isAvailable(profileID: String) async -> Bool { installed && profileID == ModelProfile.default.id }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }
}

private actor InstalledUnloadedDiarizer: SpeakerDiarizer {
    func isReady() async -> Bool { false }
    func isInstalled() async -> Bool { true }
    func feed(_ chunk: AudioChunk) async {}
    func speaker(atMs: Int) async -> String? { nil }
    func finish() async {}
}

/// S1-mini is part of every transcript by default, so the Models page has to show
/// it as installed and running, not as an optional extra.
private actor CancellationAwareASRProvider: ASRModelProvider {
    private(set) var started = false
    private(set) var cancelled = false

    func isAvailable(profileID: String) async -> Bool { false }

    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        started = true
        do {
            try await Task.sleep(for: .seconds(20))
        } catch {
            cancelled = true
            throw error
        }
    }
}

private actor CatalogASRProvider: ASRModelRemoving {
    private var installedIDs: Set<String>
    private var preparedIDs: [String] = []
    private var removedIDs: [String] = []

    init(installedIDs: Set<String>) { self.installedIDs = installedIDs }

    func isAvailable(profileID: String) async -> Bool {
        installedIDs.contains(profileID)
    }

    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        preparedIDs.append(profileID)
        installedIDs.insert(profileID)
        progress(1)
    }

    func remove(profileID: String) async throws {
        removedIDs.append(profileID)
        installedIDs.remove(profileID)
    }

    func preparedProfiles() -> [String] { preparedIDs }
    func removedProfiles() -> [String] { removedIDs }
}

@MainActor
final class ModelsViewTests: XCTestCase {
    func testFourStreamingRowsAreIndependent() async throws {
        let provider = CatalogASRProvider(installedIDs: [
            ModelProfile.default.id, ModelProfile.qwen3ASR06B.id,
        ])
        let vm = ModelsViewModel(asrModels: provider,
                                 asrModelsByRuntime: [.audioCpp: provider])
        await vm.refresh()
        let speech = vm.items.filter { $0.kind == .speech }
        XCTAssertEqual(speech.count, 4)
        XCTAssertEqual(speech.filter(\.isActive).map(\.id), [ModelProfile.default.id])
        XCTAssertEqual(speech.filter { $0.state == .installed }.count, 2)
        XCTAssertEqual(speech.first { $0.id == ModelProfile.voxtralRealtime.id }?.state, .idle)
        XCTAssertTrue(vm.matches(speech[1], query: "Qwen"))
        XCTAssertFalse(vm.matches(speech[1], query: "Voxtral"))
    }

    func testActivationFailureKeepsExistingModelSelected() async throws {
        let provider = CatalogASRProvider(installedIDs: Set(ModelProfile.streamingProfiles.map(\.id)))
        let vm = ModelsViewModel(asrModels: provider,
                                 asrModelsByRuntime: [.audioCpp: provider],
                                 onActivate: { _ in false })
        await vm.refresh()
        let didActivate = await vm.activate(ModelProfile.qwen3ASR06B.id)
        XCTAssertFalse(didActivate)
        XCTAssertEqual(vm.items.filter { $0.kind == .speech && $0.isActive }.map(\.id),
                       [ModelProfile.default.id])
        XCTAssertNotNil(vm.actionErrors[ModelProfile.qwen3ASR06B.id])
    }

    func testSuccessfulActivationAndRemovalDoNotTouchOtherInstalledModels() async throws {
        let provider = CatalogASRProvider(installedIDs: Set(ModelProfile.streamingProfiles.map(\.id)))
        let vm = ModelsViewModel(asrModels: provider,
                                 asrModelsByRuntime: [.audioCpp: provider],
                                 onActivate: { $0 == ModelProfile.qwen3ASR06B.id })
        await vm.refresh()
        let activated = await vm.activate(ModelProfile.qwen3ASR06B.id)
        XCTAssertTrue(activated)
        XCTAssertEqual(vm.activeName, ModelProfile.qwen3ASR06B.displayName)
        let didRemoveActive = await vm.remove(ModelProfile.qwen3ASR06B.id)
        XCTAssertFalse(didRemoveActive,
                       "The active profile must not be deletable")
        let removed = await vm.remove(ModelProfile.voxtralRealtime.id)
        XCTAssertTrue(removed)
        let removedIDs = await provider.removedProfiles()
        XCTAssertEqual(removedIDs, [ModelProfile.voxtralRealtime.id])
        XCTAssertEqual(vm.items.first { $0.id == ModelProfile.voxtralRealtime.id }?.state, .idle)
        XCTAssertEqual(vm.items.first { $0.id == ModelProfile.default.id }?.state, .installed)
    }

    func testExplicitOptionalModelDownloadTargetsRequestedProfile() async throws {
        let provider = CatalogASRProvider(installedIDs: [ModelProfile.default.id])
        let vm = ModelsViewModel(asrModels: provider,
                                 asrModelsByRuntime: [.audioCpp: provider])
        await vm.refresh()
        vm.download(ModelProfile.voxtralRealtime.id)
        for _ in 0..<100 {
            if await provider.preparedProfiles().contains(ModelProfile.voxtralRealtime.id) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let prepared = await provider.preparedProfiles()
        XCTAssertEqual(prepared, [ModelProfile.voxtralRealtime.id])
        vm.cancel(ModelProfile.voxtralRealtime.id)
    }

    func testInstalledSpeakerModelDoesNotNeedToBeLoadedToAppearInstalled() async throws {
        let vm = ModelsViewModel(models: FakeModelProvider(asrURL: nil, llmURL: nil),
                                 diarizer: InstalledUnloadedDiarizer())
        await vm.refresh()
        let speaker = try XCTUnwrap(vm.items.first { $0.kind == .meetings })
        XCTAssertEqual(speaker.state, .installed)
        XCTAssertTrue(speaker.isActive)
    }

    private func makeModel(llm: URL? = URL(fileURLWithPath: "/tmp/s1-mini.gguf"),
                           cleanupEnabled: @escaping @MainActor () -> Bool = { true })
        -> (ModelsViewModel, FakeModelProvider) {
        let models = FakeModelProvider(asrURL: URL(fileURLWithPath: "/tmp/asr"),
                                       llmURL: llm)
        let vm = ModelsViewModel(models: models,
                                 asrModels: InstalledASRProvider(installed: true),
                                 diarizer: FakeSpeakerDiarizer(ready: true),
                                 cleanupEnabled: cleanupEnabled)
        return (vm, models)
    }

    func testS1MiniIsInstalledAndActiveByDefault() async throws {
        let (vm, _) = makeModel()
        await vm.refresh()
        let cleanup = try XCTUnwrap(vm.items.first { $0.kind == .cleanup })
        XCTAssertEqual(cleanup.state, .installed)
        XCTAssertTrue(cleanup.isActive, "Cleanup runs on every dictation unless the owner turns it off.")
        XCTAssertEqual(vm.installedCount, 3)
        XCTAssertEqual(vm.missingCount, 4)
    }

    /// Turning cleanup off in Settings leaves the model on disk; only its `Active`
    /// badge changes. The row must not claim to be running.
    func testCleanupStaysInstalledButIdleWhenTheSettingIsOff() async throws {
        let (vm, _) = makeModel(cleanupEnabled: { false })
        await vm.refresh()
        let cleanup = try XCTUnwrap(vm.items.first { $0.kind == .cleanup })
        XCTAssertEqual(cleanup.state, .installed)
        XCTAssertFalse(cleanup.isActive)
        let speech = try XCTUnwrap(vm.items.first { $0.kind == .speech })
        XCTAssertTrue(speech.isActive)
    }

    func testSpeechRowNameComesFromTheProfileRegistry() throws {
        let profile = ModelProfile.default
        let vm = ModelsViewModel(asrProfile: profile.id)
        let speech = try XCTUnwrap(vm.items.first { $0.kind == .speech })
        XCTAssertEqual(speech.name, profile.displayName)
    }

    /// "Download all" is the default path, so it must include S1-mini.
    func testDownloadAllIncludesCleanup() throws {
        let (vm, _) = makeModel(llm: nil)
        vm.downloadAll()
        let cleanup = try XCTUnwrap(vm.items.first { $0.kind == .cleanup })
        XCTAssertEqual(cleanup.state, .downloading(0))
        for item in vm.items { vm.cancel(item.id) }
    }

    /// The reported bug: a speech model downloaded during onboarding showed a
    /// Download button here, and tapping it fetched a second copy. The row must
    /// read the port onboarding used. `ModelProvider`'s ASR manifest is empty, so
    /// asking it reports "not installed" for a model that is on disk.
    func testSpeechRowReadsTheRecognizerNotTheModelStore() async throws {
        let store = FakeModelProvider(asrURL: nil, llmURL: URL(fileURLWithPath: "/tmp/s1-mini.gguf"))
        let vm = ModelsViewModel(models: store,
                                 asrModels: InstalledASRProvider(installed: true),
                                 diarizer: FakeSpeakerDiarizer(ready: true))
        await vm.refresh()
        let speech = try XCTUnwrap(vm.items.first { $0.kind == .speech })
        XCTAssertEqual(speech.state, .installed)
        XCTAssertTrue(speech.isActive)
        XCTAssertEqual(vm.missingCount, 1)
        XCTAssertFalse(vm.isChecking)
    }

    func testSpeechRowShowsOtherRuntimeInstallAndTracksTheSelectedRuntime() async throws {
        let vm = ModelsViewModel(
            models: FakeModelProvider(asrURL: nil, llmURL: nil),
            asrModelsByRuntime: [
                .audioCpp: InstalledASRProvider(installed: true),
                .sherpaOnnx: InstalledASRProvider(installed: false),
            ], asrRuntime: .sherpaOnnx)

        await vm.refresh()
        let sherpaSpeech = try XCTUnwrap(vm.items.first { $0.kind == .speech })
        XCTAssertEqual(sherpaSpeech.state, .installed)
        XCTAssertFalse(sherpaSpeech.isActive)
        XCTAssertTrue(sherpaSpeech.detail.contains("audio.cpp"))

        await vm.updateASRSelection(runtime: .audioCpp, profile: ModelProfile.default.id)

        let fluidSpeech = try XCTUnwrap(vm.items.first { $0.kind == .speech })
        XCTAssertEqual(fluidSpeech.state, .installed)
        XCTAssertTrue(fluidSpeech.detail.contains("audio.cpp"))
    }

    /// A row offers Download only after the disk has answered, so a page visit
    /// never looks like it is asking for the model again.
    func testDownloadIsNotOfferedBeforeTheFirstCheck() async throws {
        let vm = ModelsViewModel(models: FakeModelProvider(asrURL: nil, llmURL: nil),
                                 asrModels: InstalledASRProvider(installed: false))
        XCTAssertTrue(vm.isChecking)
        XCTAssertFalse(vm.showsDownloadRemaining)
        await vm.refresh()
        XCTAssertFalse(vm.isChecking)
        XCTAssertTrue(vm.showsDownloadRemaining)
        XCTAssertEqual(vm.remainingDownloadCount, 4)
        vm.download(ModelsViewModel.enhancementID)
        XCTAssertFalse(vm.showsDownloadRemaining)
        XCTAssertEqual(vm.remainingDownloadCount, 3)
        vm.cancel(ModelsViewModel.enhancementID)
        XCTAssertTrue(vm.showsDownloadRemaining)
    }

    /// A cancelled row cannot be repainted by a late progress callback.
    func testCancelStopsTheUnderlyingSpeechDownloadTask() async throws {
        let speech = CancellationAwareASRProvider()
        let vm = ModelsViewModel(asrModels: speech)
        vm.download(ModelProfile.default.id)
        for _ in 0..<100 {
            if await speech.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await speech.started
        XCTAssertTrue(started, "The fake provider must start before cancellation is assessed.")
        vm.cancel(ModelProfile.default.id)
        for _ in 0..<100 {
            if await speech.cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let cancelled = await speech.cancelled
        XCTAssertTrue(cancelled, "Cancelling a download must cancel its actual async task.")
        let model = try XCTUnwrap(vm.items.first { $0.kind == .speech })
        XCTAssertEqual(model.state, .idle)
        XCTAssertFalse(model.isActive)
    }

    func testCancelReturnsCleanupToIdle() async throws {
        let (vm, _) = makeModel(llm: nil)
        await vm.refresh()
        try XCTUnwrap(vm.items.first { $0.kind == .cleanup })
        vm.download("s1-mini")
        vm.cancel("s1-mini")
        let cleanup = try XCTUnwrap(vm.items.first { $0.kind == .cleanup })
        XCTAssertEqual(cleanup.state, .idle)
        XCTAssertFalse(cleanup.isActive)
    }
}

@MainActor
final class EnhancementModelTests: XCTestCase {
    func testDeepFilterNetIsRequiredAndShownByDefault() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.speechEnhancementEnabled)
        let vm = ModelsViewModel()
        let item = try XCTUnwrap(vm.items.first { $0.kind == .enhancement })
        XCTAssertEqual(item.name, "DeepFilterNet 3")
        XCTAssertTrue(item.detail.contains("Required"))
        XCTAssertFalse(item.isActive)
    }
    func testDisabledSettingSurvivesPersistence() throws {
        var settings = AppSettings()
        settings.speechEnhancementEnabled = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.speechEnhancementEnabled)
    }
}
