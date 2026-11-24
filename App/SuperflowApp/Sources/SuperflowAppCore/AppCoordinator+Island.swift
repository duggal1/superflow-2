import SuperflowFeatureIsland
import SuperflowFeatureIntelligence
import SwiftUI
import SuperflowGestureKit

extension AppCoordinator {
    func configureIslandActions(_ islandModel: IslandModel, environment: AppEnvironment) {
        islandBridge?.model = islandModel
        islandModel.openIntelligence = { [weak self] in self?.openIntelligenceCompose() }
        islandModel.intelligenceContent = { [weak self, weak islandModel] state in
            guard let self, let islandModel else { return nil }
            let recording = islandModel.phase == .meetingPanel
            switch state {
            case .compose: break
            case .meetingLive where recording: break
            default: return nil
            }
            return AnyView(SuperflowFeatureIntelligence.IntelligenceContent(
                model: environment.intelligenceIsland.model,
                recording: recording,
                liveText: islandModel.prefs.liveText ? islandModel.live.text : "",
                onRecord: { [weak self] in self?.toggleIntelligenceRecording() },
                onDismiss: { [weak islandModel] in islandModel?.send(.dismissed) },
                onConfiguration: { [weak self] in self?.mainWindowController.show(.intelligence) }
            ))
        }
        environment.intelligenceIsland.model.liveTranscriptProvider = { [weak self] in
            guard let self, self.menuBarController.meetingState.isActive,
                  let document = await environment.meetingEngine.currentDocument else { return "" }
            return String(document.turns.filter { !$0.isGap }.map {
                "[\($0.timestampLabel)] \($0.speakerName): \($0.text)"
            }.joined(separator: "\n").suffix(7_000))
        }
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
