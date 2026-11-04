import Foundation
import SuperflowKernel

extension AppCoordinator {
    /// Activation never interrupts recording and only persists a compatible,
    /// installed ASR profile. The model selection is owned by the Models page.
    func activateSpeechModel(_ profile: String) async -> Bool {
        guard let environment,
              !menuBarController.sessionState.isActive,
              !menuBarController.meetingState.isActive,
              ModelProfile.byID(profile).id == profile,
              ModelProfile.byID(profile).supportsLiveDictation,
              await environment.recognizer.isAvailable(profileID: profile) else {
            return false
        }
        var updated = settings
        updated.asrProfile = profile
        await environment.settingsStore.save(updated)
        await applySettings(updated)
        return true
    }
}
