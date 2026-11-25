import Foundation
import SuperflowFeatureIsland
import SuperflowMeetingIntelligence
import SuperflowKernel

@MainActor
extension AppCoordinator {
    /// Left Control starts and stops a dedicated capture. The existing ASR and
    /// journal are reused; command text is never passed through S1 or pasted.
    func toggleVoiceCommand() {
        guard voiceCommandTask == nil else { return }
        if voiceCommandActive {
            voiceCommandTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.finishVoiceCommand() }
                self.islandBridge?.holdEnded()
                guard let outcome = await self.menuBarController.stopVoiceCommand(),
                      !outcome.text.isEmpty,
                      !Task.isCancelled,
                      UserDefaults.standard.bool(forKey: "jev.enabled") else { return }
                do {
                    let credentials = ReflectionCredentials(service: "Superflow.Jev")
                    guard let key = try credentials.load(), !key.isEmpty else { throw JevVoiceError.missingKey }
                    let plan = try await JevVoiceClient(apiKey: key).choose(outcome.text)
                    try Task.checkCancellation()
                    try await VoiceActionExecutor.run(plan)
                    self.islandBridge?.notice(IslandNotice(kind: .info, title: "Command complete.", detail: plan.description))
                } catch is CancellationError {
                    return
                } catch {
                    self.islandBridge?.notice(IslandNotice(kind: .info, title: "Command not run.", detail: error.localizedDescription))
                }
            }
            return
        }
        guard UserDefaults.standard.bool(forKey: "jev.enabled"),
              menuBarController.canStartDictation, gesture.state == .idle else { return }
        voiceCommandActive = true
        islandBridge?.model?.voiceCommandMode = true
        islandBridge?.holdBegan()
        voiceCommandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = await self.menuBarController.startDictation(mode: .handsFree, commandCapture: true)
            guard !Task.isCancelled else { return }
            if started {
                self.islandBridge?.handsFreeBegan()
                self.voiceCommandTask = nil
            } else {
                self.finishVoiceCommand()
                self.islandBridge?.refused("Voice capture could not start.")
            }
        }
    }

    func cancelVoiceCommand() {
        voiceCommandTask?.cancel()
        voiceCommandTask = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.menuBarController.cancel(.dictation)
            self.islandBridge?.cancelled()
            self.finishVoiceCommand()
        }
    }

    private func finishVoiceCommand() {
        voiceCommandTask = nil
        voiceCommandActive = false
        islandBridge?.model?.voiceCommandMode = false
    }
}
