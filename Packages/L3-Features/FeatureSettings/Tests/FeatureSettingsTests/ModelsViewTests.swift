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
    func isAvailable(profileID: String) async -> Bool { installed }
    func prepare(profileID: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }
}

/// S1-mini is part of every transcript by default, so the Models page has to show
/// it as installed and running, not as an optional extra.
@MainActor
final class ModelsViewTests: XCTestCase {
    private func makeModel(llm: URL? = URL(fileURLWithPath: "/tmp/s1-mini.gguf"),
                           cleanupEnabled: @escaping @MainActor () -> Bool = { true })
        -> (ModelsViewModel, FakeModelProvider) {
        let models = FakeModelProvider(asrURL: URL(fileURLWithPath: "/tmp/asr"),
                                       llmURL: llm)
        let vm = ModelsViewModel(models: models,
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
        XCTAssertEqual(vm.missingCount, 1)
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
        let profile = ModelProfile.parakeetEOU120M
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

    /// A row offers Download only after the disk has answered, so a page visit
    /// never looks like it is asking for the model again.
    func testDownloadIsNotOfferedBeforeTheFirstCheck() async throws {
        let vm = ModelsViewModel(models: FakeModelProvider(asrURL: nil, llmURL: nil),
                                 asrModels: InstalledASRProvider(installed: false))
        XCTAssertTrue(vm.isChecking)
        await vm.refresh()
        XCTAssertFalse(vm.isChecking)
    }

    /// A cancelled row cannot be repainted by a late progress callback.
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
