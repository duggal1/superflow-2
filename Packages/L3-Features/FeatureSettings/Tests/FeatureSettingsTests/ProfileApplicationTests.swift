import Foundation
import SuperflowContextProfiles
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowFeatureSettings

/// The Context profile picker is cut from Settings (pass 3 §9.1), but the
/// view-model application path stays: a profile is still a draft until Save and
/// still offers Undo. These tests cover that path, not the deleted picker.
@MainActor
final class ProfileApplicationTests: XCTestCase {
    private var store: InMemorySettings!
    private var login: FakeLaunchAtLogin!
    private var models: FakeModelProvider!

    override func setUp() async throws {
        store = InMemorySettings(AppSettings.default)
        login = FakeLaunchAtLogin(enabled: false)
        models = FakeModelProvider(asrURL: URL(fileURLWithPath: "/tmp/asr"),
                                   llmURL: URL(fileURLWithPath: "/tmp/llm"))
    }

    private func makeModel() -> SettingsViewModel {
        SettingsViewModel(store: store, models: models, launchAtLogin: login)
    }

    func testApplyingAProfileTouchesOnlyProfileFields() async {
        let model = makeModel()
        await model.load()
        model.settings.displayName = "Harshit"
        model.settings.typingWPM = 60

        model.applyProfile(.code)

        XCTAssertEqual(model.settings.cleanupContext, "code")
        XCTAssertTrue(model.settings.codeSpeakEnabled)
        XCTAssertEqual(model.settings.displayName, "Harshit")
        XCTAssertEqual(model.settings.typingWPM, 60)
        XCTAssertTrue(model.hasChanges, "a profile is a draft until Save")
    }

    func testApplyingAProfileOffersUndo() async {
        let model = makeModel()
        await model.load()
        model.settings.cleanupContext = "general"
        model.settings.codeSpeakEnabled = false

        model.applyProfile(.code)
        XCTAssertEqual(model.toast.current?.actionTitle, "Undo")

        model.toast.performAction()
        XCTAssertEqual(model.settings.cleanupContext, "general")
        XCTAssertFalse(model.settings.codeSpeakEnabled)
    }

    func testApplyingTheActiveProfileDoesNotToast() async {
        let model = makeModel()
        await model.load()
        model.applyProfile(.code)
        model.toast.dismiss()

        model.applyProfile(.code)
        XCTAssertNil(model.toast.current)
    }
}
