import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureSettings

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var store: InMemorySettings!
    private var login: FakeLaunchAtLogin!
    private var models: FakeModelProvider!

    override func setUp() async throws {
        var initial = AppSettings.default
        initial.displayName = "Harshit"
        initial.typingWPM = 60
        store = InMemorySettings(initial)
        login = FakeLaunchAtLogin(enabled: true)
        models = FakeModelProvider(asrURL: URL(fileURLWithPath: "/tmp/asr"),
                                   llmURL: URL(fileURLWithPath: "/tmp/llm"))
    }

    private func makeModel(diagnostics: (any DiagnosticsExporting)? = nil,
                           onChange: (@MainActor (AppSettings) -> Void)? = nil) -> SettingsViewModel {
        SettingsViewModel(store: store, models: models, launchAtLogin: login,
                          diagnostics: diagnostics, onSettingsSaved: onChange)
    }

    func testLoadPopulatesSettingsAndModelState() async {
        let model = makeModel()
        await model.load()

        XCTAssertEqual(model.settings.displayName, "Harshit")
        XCTAssertEqual(model.settings.typingWPM, 60)
        XCTAssertTrue(model.settings.launchAtLogin, "the stored flag syncs to the real login item")
        XCTAssertTrue(model.asrReady)
        XCTAssertTrue(model.cleanupReady)
        XCTAssertFalse(model.hasChanges)
        XCTAssertNil(model.error)
    }

    func testEditingRevertAndReset() async {
        let model = makeModel()
        await model.load()

        model.settings.typingWPM = 90
        XCTAssertTrue(model.hasChanges)
        XCTAssertTrue(model.canSave)

        model.revert()
        XCTAssertEqual(model.settings.typingWPM, 60)
        XCTAssertFalse(model.hasChanges)

        model.settings.displayName = "Someone else"
        model.resetToDefaults()
        XCTAssertEqual(model.settings.displayName, "You")
        XCTAssertEqual(model.settings.typingWPM, 40)
        XCTAssertTrue(model.hasChanges)
    }

    func testValidationRejectsBadTimingsLineBreaksAndName() async {
        let model = makeModel()
        await model.load()

        model.settings.gesture.holdMs = 50
        model.settings.gesture.doubleTapMs = 900
        model.settings.gesture.meetingHoldMs = 100
        model.settings.typingWPM = 5
        model.settings.displayName = "   "
        model.settings.lineFormat.minWords = 50
        model.settings.lineFormat.preferredMax = 30
        model.settings.lineFormat.hardMax = 40
        model.settings.retentionDays = 0
        model.settings.cleanupWorkers = 12

        let issues = Set(model.issues)
        XCTAssertTrue(issues.contains(.holdOutOfRange))
        XCTAssertTrue(issues.contains(.doubleTapOutOfRange))
        XCTAssertTrue(issues.contains(.meetingHoldOutOfRange))
        XCTAssertTrue(issues.contains(.typingSpeedOutOfRange))
        XCTAssertTrue(issues.contains(.displayNameEmpty))
        XCTAssertTrue(issues.contains(.lineBreakOutOfOrder))
        XCTAssertTrue(issues.contains(.retentionOutOfRange))
        XCTAssertTrue(issues.contains(.cleanupWorkersOutOfRange))
        XCTAssertFalse(model.canSave)

        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(model.toast.current?.style, .warning)
        let persisted = await store.load()
        XCTAssertEqual(persisted.gesture.holdMs, 200, "invalid settings never reach the store")
    }

    func testSavePersistsAndNotifies() async {
        var received: AppSettings?
        let model = makeModel(onChange: { received = $0 })
        await model.load()

        model.settings.typingWPM = 75
        model.settings.cleanupEnabled = false
        let saved = await model.save()

        XCTAssertTrue(saved)
        XCTAssertEqual(model.toast.current?.style, .success)
        XCTAssertFalse(model.hasChanges)
        let persisted = await store.load()
        XCTAssertEqual(persisted.typingWPM, 75)
        XCTAssertFalse(persisted.cleanupEnabled)
        XCTAssertEqual(received?.typingWPM, 75)
    }

    func testSaveTrimsDisplayName() async {
        let model = makeModel()
        await model.load()
        model.settings.displayName = "  Harshit  "
        let saved = await model.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(model.settings.displayName, "Harshit")
    }

    func testLaunchAtLoginIsAppliedAndFailureReverts() async {
        let model = makeModel()
        await model.load()
        model.settings.launchAtLogin = false
        let savedOff = await model.save()
        XCTAssertTrue(savedOff)
        var enabled = await login.enabled
        XCTAssertFalse(enabled)
        var calls = await login.calls
        XCTAssertEqual(calls, [false])

        model.toast.dismiss()
        await login.setFailSet(true)
        model.settings.launchAtLogin = true
        let savedOn = await model.save()
        XCTAssertTrue(savedOn)
        enabled = await login.enabled
        XCTAssertFalse(enabled, "the toggle reverts when SMAppService refuses")
        XCTAssertFalse(model.settings.launchAtLogin)
        XCTAssertEqual(model.toast.current?.style, .error)
        calls = await login.calls
        XCTAssertEqual(calls, [false, true])
    }

    func testRetentionLabelsAndOptions() {
        XCTAssertEqual(SettingsViewModel.retentionLabel(for: nil), "Keep forever")
        XCTAssertEqual(SettingsViewModel.retentionLabel(for: 1), "After 1 day")
        XCTAssertEqual(SettingsViewModel.retentionLabel(for: 30), "After 30 days")
        XCTAssertEqual(SettingsViewModel.retentionOptions.compactMap { $0 }, [7, 30, 90, 180, 365])
    }

    func testProfileSelectionUpdatesNameAndAvailability() async {
        await models.setASRURL(nil)
        let model = makeModel()
        await model.load()
        XCTAssertFalse(model.asrReady)
        XCTAssertEqual(model.profileName("nemotron-streaming-0.6b"),
                       "Nemotron Speech Streaming 0.6B")

        model.setProfile("nemotron-streaming-0.6b")
        await model.refreshModelState()
        XCTAssertEqual(model.settings.asrProfile, "nemotron-streaming-0.6b")
        XCTAssertEqual(model.profile.id, "nemotron-streaming-0.6b")
        XCTAssertEqual(model.profileStatusLabel("parakeet-unified-0.6b"), "Experimental")
        XCTAssertTrue(model.profileOptions.contains("parakeet-unified-0.6b"))
        XCTAssertTrue(model.profileOptions.contains("nemotron-3.5-asr-streaming-0.6b"))
        XCTAssertFalse(model.profileOptions.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertEqual(model.profileStatusLabel("parakeet-tdt-0.6b-v3"), "Not for dictation")
    }

    func testBatchModelCannotBeSelectedForLiveDictation() async {
        let model = makeModel()
        await model.load()

        model.setProfile("parakeet-tdt-0.6b-v3")

        // The batch profile is refused, so the previous selection stands.
        XCTAssertEqual(model.settings.asrProfile, ModelProfile.nemotron35Streaming.id)
        XCTAssertEqual(model.toast.current?.style, .warning)
        XCTAssertFalse(ModelProfile.parakeetTDTV3.supportsLiveDictation)
    }

    func testDownloadASRModelHandlesSuccessAndFailure() async {
        await models.setASRURL(nil)
        let model = makeModel()
        await model.load()
        await model.downloadASRModel()
        XCTAssertFalse(model.asrReady)
        XCTAssertEqual(model.toast.current?.style, .error)

        await models.setASRURL(URL(fileURLWithPath: "/tmp/asr"))
        model.toast.dismiss()
        await model.downloadASRModel()
        XCTAssertTrue(model.asrReady)
        XCTAssertEqual(model.toast.current?.style, .success)
        XCTAssertNil(model.asrProgress)
    }

    func testDownloadCleanupModel() async {
        await models.setLLMURL(nil)
        let model = makeModel()
        await model.load()
        XCTAssertFalse(model.cleanupReady)

        await model.downloadCleanupModel()
        XCTAssertFalse(model.cleanupReady)
        XCTAssertEqual(model.toast.current?.style, .error)

        await models.setLLMURL(URL(fileURLWithPath: "/tmp/llm"))
        model.toast.dismiss()
        await model.downloadCleanupModel()
        XCTAssertTrue(model.cleanupReady)
        XCTAssertEqual(model.toast.current?.style, .success)
    }

    func testDownloadDiarizationModelUpdatesReadinessAndProgress() async {
        let diarizer = SettingsTestDiarizer()
        let model = SettingsViewModel(store: store, models: models, diarizer: diarizer)
        await model.load()
        XCTAssertFalse(model.diarizationReady)

        await model.downloadDiarizationModel()

        XCTAssertTrue(model.diarizationReady)
        XCTAssertFalse(model.isDownloadingDiarization)
        XCTAssertNil(model.diarizationProgress)
        XCTAssertEqual(model.toast.current?.style, .success)
    }

    func testDiagnosticsExportWritesAndReportsFailure() async {
        let exporter = FakeDiagnosticsExporter()
        let model = makeModel(diagnostics: exporter)
        await model.load()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("diagnostics.json")
        let ok = await model.exportDiagnostics(to: url)
        XCTAssertTrue(ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(model.lastDiagnosticsExport, url)
        let urls = await exporter.urls
        XCTAssertEqual(urls, [url])

        await exporter.setFail(true)
        model.toast.dismiss()
        let failed = await model.exportDiagnostics(to: url)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.toast.current?.style, .error)
    }
}

private actor SettingsTestDiarizer: SpeakerDiarizer {
    private var ready = false

    func isReady() async -> Bool { ready }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        ready = true
        progress(1)
    }

    func beginSession() async {}
    func feed(_ chunk: AudioChunk) async {}
    func speaker(atMs: Int) async -> String? { nil }
    func finish() async {}
}
