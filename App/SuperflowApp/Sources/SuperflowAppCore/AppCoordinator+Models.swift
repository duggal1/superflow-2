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
        // Do not commit an alternate model that cannot start a native
        // streaming session. The previous settings survive preparation failure.
        do {
            try await environment.recognizer.warmUp(profile: profile)
        } catch {
            return false
        }
        guard !menuBarController.sessionState.isActive,
              !menuBarController.meetingState.isActive else { return false }
        var updated = settings
        updated.asrRuntime = .audioCpp
        updated.asrProfile = profile
        await environment.settingsStore.save(updated)
        await applySettings(updated)
        return true
    }
}
