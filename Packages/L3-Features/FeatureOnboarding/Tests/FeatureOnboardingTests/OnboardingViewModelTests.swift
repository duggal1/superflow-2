import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureOnboarding

private actor FakePracticeDictation: PracticeDictation {
    private let text: String
    private let fail: Bool

    init(text: String = "This is a practice dictation.", fail: Bool = false) {
        self.text = text
        self.fail = fail
    }

    func transcribe() async throws -> String {
        if fail { throw FakePracticeError.offline }
        return text
    }
}

private enum FakePracticeError: LocalizedError {
    case offline
    var errorDescription: String? { "The practice microphone is unavailable." }
}

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var permissions: FakePermissionGate!
    private var globe: FakeGlobeKeyProbe!
    private var models: FakeModelProvider!
    private var store: InMemorySettings!

    override func setUp() async throws {
        permissions = FakePermissionGate(all: .denied)
        globe = FakeGlobeKeyProbe(.doNothing)
        models = FakeModelProvider(asrURL: URL(fileURLWithPath: "/tmp/asr"),
                                   llmURL: URL(fileURLWithPath: "/tmp/llm"))
        store = InMemorySettings()
    }

    private func makeModel(practice: (any PracticeDictation)? = nil,
                           onFinish: (@MainActor (AppSettings) -> Void)? = nil)
        -> OnboardingViewModel {
        OnboardingViewModel(permissions: permissions, globe: globe, models: models,
                            cleanupModels: models, settingsStore: store, practice: practice,
                            onFinish: onFinish ?? { _ in })
    }

    private func grantRequiredPermissions() async {
        for permission in OnboardingViewModel.requiredPermissions {
            await permissions.set(permission, .granted)
        }
    }

    private func advanceTo(_ target: OnboardingStep, in model: OnboardingViewModel) async {
        var guardCount = 0
        while model.step != target && guardCount < 12 {
            if model.canAdvance {
                await model.advance()
            } else {
                await model.skipCurrent()
            }
            guardCount += 1
        }
    }

    func testStepOrderAndProgress() {
        XCTAssertEqual(OnboardingStep.allCases.map(\.rawValue),
                       ["welcome", "permissions", "models", "done"])
        XCTAssertEqual(OnboardingStep.welcome.index, 0)
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.welcome.next, .permissions)
        XCTAssertEqual(OnboardingStep.permissions.next, .models)
        XCTAssertEqual(OnboardingStep.models.next, .done)
        XCTAssertEqual(OnboardingStep.done.previous, .models)
        XCTAssertEqual(OnboardingStep.done.index, 3)
        XCTAssertNil(OnboardingStep.done.next)
        XCTAssertEqual(OnboardingStep.done.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(OnboardingStep.models.progress, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testPermissionsBlockAdvanceUntilGranted() async {
        let model = makeModel()
        await model.load()
        XCTAssertEqual(model.step, .welcome)

        await model.advance()
        XCTAssertEqual(model.step, .permissions)
        XCTAssertFalse(model.canAdvance)
        XCTAssertFalse(model.primaryEnabled)
        XCTAssertEqual(model.grantedCount, 0)

        await model.request(.microphone)
        XCTAssertEqual(model.status(for: .microphone), .denied)
        XCTAssertFalse(model.canAdvance)

        await grantRequiredPermissions()
        await model.refreshPermissions()
        XCTAssertEqual(model.grantedCount, 3)
        XCTAssertTrue(model.permissionsGranted)
        XCTAssertTrue(model.canAdvance)
        XCTAssertTrue(model.primaryEnabled)

        await model.advance()
        XCTAssertEqual(model.step, .models)
    }

    func testSkipPermissionsStillAdvances() async {
        let model = makeModel()
        await model.load()
        await model.advance()
        XCTAssertEqual(model.step, .permissions)

        await model.skipCurrent()
        XCTAssertEqual(model.step, .models)
        XCTAssertTrue(model.permissionsSkipped)
    }

    func testGlobeConflictIsWarnedButNotBlocking() async {
        await grantRequiredPermissions()
        await globe.set(.emojiAndSymbols)
        let model = makeModel()
        await model.load()

        await advanceTo(.models, in: model)
        XCTAssertEqual(model.globeAction, .emojiAndSymbols)
        XCTAssertTrue(model.globeConflict)
        XCTAssertTrue(model.globeChecked)
        XCTAssertTrue(model.canAdvance)

        await model.advance()
        XCTAssertEqual(model.step, .done)
    }

    func testModelReadySkipsDownload() async {
        await grantRequiredPermissions()
        let model = makeModel()
        await model.load()

        await advanceTo(.models, in: model)
        XCTAssertTrue(model.speechReady)
        XCTAssertTrue(model.canAdvance)
        XCTAssertEqual(model.speechName, ModelProfile.nemotron35Streaming.displayName)
        XCTAssertEqual(model.speechDetail, "Ready")
        XCTAssertFalse(model.needsDownload)
        XCTAssertEqual(model.primaryTitle, "Continue")
        XCTAssertNil(model.speechError)
    }

    func testModelFailureCanBeSkipped() async {
        await models.setASRURL(nil)
        await grantRequiredPermissions()
        let model = makeModel()
        await model.load()

        await advanceTo(.models, in: model)
        XCTAssertFalse(model.speechReady)
        XCTAssertFalse(model.canAdvance)
        XCTAssertTrue(model.needsDownload)
        XCTAssertEqual(model.primaryTitle, "Download")

        await model.downloadSpeech()
        XCTAssertNotNil(model.speechError)
        XCTAssertFalse(model.speechReady)
        XCTAssertEqual(model.speechDetail, "Download failed")
        XCTAssertEqual(model.toast.current?.style, .error)

        await model.skipCurrent()
        XCTAssertEqual(model.step, .done)
        XCTAssertTrue(model.speechSkipped)
    }

    func testPrimaryActionDownloadsThenContinues() async {
        await models.setASRURL(nil)
        await grantRequiredPermissions()
        let model = makeModel()
        await model.load()
        await advanceTo(.models, in: model)

        // A successful resume leaves the user on the models step with the model ready.
        await models.setASRURL(URL(fileURLWithPath: "/tmp/asr"))
        await model.performPrimaryAction()
        XCTAssertEqual(model.step, .models)
        XCTAssertTrue(model.speechReady)
        XCTAssertEqual(model.primaryTitle, "Continue")

        await model.performPrimaryAction()
        XCTAssertEqual(model.step, .done)
    }

    func testCleanupStepReportsReadyAndCanBeDisabled() async {
        await grantRequiredPermissions()
        let model = makeModel()
        await model.load()

        await advanceTo(.models, in: model)
        XCTAssertTrue(model.cleanupAvailable)
        XCTAssertTrue(model.cleanupReady, "an installed S1-mini GGUF must resolve as ready")
        XCTAssertEqual(model.cleanupDetail, "Ready")

        await model.setCleanupWanted(false)
        XCTAssertFalse(model.cleanupWanted)
        XCTAssertFalse(model.cleanupReady)
    }

    func testCleanupDownloadFailureIsReportedAndSkippable() async {
        await models.setLLMURL(nil)
        await grantRequiredPermissions()
        let model = makeModel()
        await model.load()

        await advanceTo(.models, in: model)
        XCTAssertFalse(model.cleanupReady)
        XCTAssertTrue(model.canAdvance, "the speech model is ready, so the step does not block")

        await model.downloadCleanupModel()
        XCTAssertNotNil(model.cleanupError)
        XCTAssertFalse(model.cleanupReady)
        XCTAssertEqual(model.cleanupDetail, "Download failed")

        await model.skipCurrent()
        XCTAssertEqual(model.step, .done)
        XCTAssertTrue(model.speechSkipped)
        XCTAssertFalse(model.cleanupWanted)
    }

    func testCleanupDownloadSuccessMarksReady() async {
        await models.setLLMURL(nil)
        await grantRequiredPermissions()
        let model = makeModel()
        await model.load()
        await advanceTo(.models, in: model)

        // The fake provider's ensureLLM fails while llmURL is nil, so restore it as if the
        // download completed and re-check, mirroring the real store writing the verified file.
        await models.setLLMURL(URL(fileURLWithPath: "/tmp/llm"))
        await model.checkCleanupModel()
        XCTAssertTrue(model.cleanupReady)
        XCTAssertTrue(model.canAdvance)
    }

    func testPracticeTranscribesIntoTheSandboxField() async {
        await grantRequiredPermissions()
        let practice = FakePracticeDictation(text: "Hello from the sandbox.")
        let model = makeModel(practice: practice)
        await model.load()
        await advanceTo(.done, in: model)
        XCTAssertTrue(model.practiceReady)

        await model.startPractice()
        XCTAssertEqual(model.practiceText, "Hello from the sandbox.")
        XCTAssertEqual(model.practiceState, .done)
        XCTAssertFalse(model.isListening)

        model.cancelPractice()
        XCTAssertEqual(model.practiceState, .idle)
    }

    func testPracticeFailureIsReported() async {
        await grantRequiredPermissions()
        let practice = FakePracticeDictation(fail: true)
        let model = makeModel(practice: practice)
        await model.load()
        await advanceTo(.done, in: model)

        await model.startPractice()
        XCTAssertEqual(model.practiceState,
                       .failed("The practice microphone is unavailable."))
        XCTAssertTrue(model.practiceText.isEmpty)
    }

    func testPracticeStaysHiddenWithoutMicrophoneOrModel() async {
        let model = makeModel(practice: FakePracticeDictation())
        await model.load()
        await advanceTo(.done, in: model)
        XCTAssertFalse(model.practiceReady)

        await grantRequiredPermissions()
        await model.refreshPermissions()
        XCTAssertTrue(model.practiceReady)
    }

    func testRequestsAndDeepLinksReachTheGate() async {
        let model = makeModel()
        await model.load()

        await model.request(.microphone)
        await model.openSystemSettings(.accessibility)

        let requested = await permissions.requested
        let opened = await permissions.opened
        XCTAssertEqual(requested, [.microphone])
        XCTAssertEqual(opened, [.accessibility])
    }

    func testFinishSavesOnboardingCompleteAndNotifies() async {
        var received: AppSettings?
        let model = makeModel(onFinish: { received = $0 })
        await model.load()
        await advanceTo(.done, in: model)

        let finished = await model.finish()
        XCTAssertTrue(finished)
        XCTAssertEqual(model.toast.current?.style, .success)
        let saved = await store.load()
        XCTAssertTrue(saved.onboardingComplete)
        XCTAssertTrue(received?.onboardingComplete == true)
    }

    /// The last step has no `next`, so `Open Superflow` must finish, not advance.
    func testPrimaryActionOnDoneSavesAndHandsOff() async {
        var received: AppSettings?
        let model = makeModel(onFinish: { received = $0 })
        await model.load()
        await advanceTo(.done, in: model)

        await model.performPrimaryAction()

        let saved = await store.load()
        XCTAssertTrue(saved.onboardingComplete)
        XCTAssertTrue(received?.onboardingComplete == true)
        XCTAssertFalse(model.isFinishing)
    }
}
