import SuperflowFeatureIsland
import SuperflowGestureKit

extension AppCoordinator {
    func configureIslandActions(_ islandModel: IslandModel, environment: AppEnvironment) {
        islandModel.showHistory = { [weak mainWindowController] in mainWindowController?.show(.history) }
        islandModel.rePaste = { [weak islandModel] transcript in
            Task { @MainActor [weak islandModel] in
                do {
                    let outcome = try await environment.textInserter.insert(transcript.text, strategy: .auto)
                    switch outcome {
                    case .pasted, .accessibility: islandModel?.send(.dismissed)
                    case .clipboardOnly, .permissionRequired, .blockedSecureField: break
                    }
                } catch {
                    // Keep the failure card available for Copy or another attempt.
                }
            }
        }
        islandModel.finishMeeting = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.gesture = GestureRecognizer(config: self.settings.gesture)
                await self.applyGestureActions([.submit(.meeting)])
            }
        }
        islandModel.cancelMeeting = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.gesture = GestureRecognizer(config: self.settings.gesture)
                await self.menuBarController.cancel(.meeting, cue: true)
                self.islandBridge?.cancelled()
            }
        }
    }
}
