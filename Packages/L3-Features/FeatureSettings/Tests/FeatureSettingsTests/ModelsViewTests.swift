import SuperflowFeatureSettings
import SuperflowKernel
import SuperflowTestKit
import SuperflowUIComponents
import XCTest

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
        XCTAssertEqual(vm.missingCount, 0)
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
