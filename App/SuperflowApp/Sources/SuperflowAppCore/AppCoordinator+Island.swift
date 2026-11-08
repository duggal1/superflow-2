import SuperflowFeatureIsland
import SuperflowGestureKit

extension AppCoordinator {
    func configureIslandActions(_ islandModel: IslandModel, environment: AppEnvironment) {
        islandBridge?.model = islandModel
        islandModel.assistantHelp = { [weak self] in self?.islandBridge?.assistantHelp() }
        islandModel.assistantDeeper = { [weak self] in self?.islandBridge?.assistantDeeper() }
        islandModel.assistantRetry = { [weak self] in self?.islandBridge?.assistantRetry() }
        islandModel.assistantCancel = { [weak self] in self?.islandBridge?.closeAssistant() }
        islandModel.assistantOpenSettings = { [weak mainWindowController] in
            mainWindowController?.show(.intelligence)
        }
        islandModel.showHistory = { [weak mainWindowController] in mainWindowController?.show(.history) }
        let knowledgeNotices = KnowledgeNoticeRouter(learning: environment.learningEngine,
                                                     island: islandModel)
        islandModel.noticeAction = { [knowledgeNotices] notice in
            knowledgeNotices.handle(notice)
        }
        Task { [weak knowledgeNotices] in
            await environment.learningEngine.setOnApplied { [weak knowledgeNotices] candidate, active in
                await knowledgeNotices?.applied(candidate, active: active)
            }
        }
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
