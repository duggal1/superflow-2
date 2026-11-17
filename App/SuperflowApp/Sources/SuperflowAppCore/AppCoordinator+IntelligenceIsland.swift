import Foundation
import SuperflowFeatureIntelligence
import SuperflowFeatureIsland
import SuperflowKernel
import SwiftUI

/// Coordinator-side entry points for the rebuilt Intelligence surface. The
/// views and model live in `SuperflowFeatureIntelligence`; this file only routes
/// Island events to them and uses the app's existing copy/history backends.
extension AppCoordinator {
    public var intelligenceModel: IntelligenceIslandModel? {
        environment?.intelligenceIsland.model
    }

    /// Right Option (or a click on the compose card) opens the typed surface.
    public func openIntelligenceCompose() {
        guard let environment else { return }
        let seam = environment.intelligenceIsland
        seam.model.show(.compose)
        // The existing assistant event still opens the shared Island card; the
        // view hosted inside it is `seam.content(for:)`.
        islandBridge?.box.send(.assistantOpened)
    }

    public func submitIntelligence(_ text: String) async {
        await intelligenceModel?.submit(text)
    }

    public func copyIntelligenceAnswer() async {
        await intelligenceModel?.copy()
    }

    public func openIntelligenceSettings() {
        guard let model = intelligenceModel else { return }
        if !model.settingsExpanded { model.toggleSettings() }
    }

    public func showIntelligenceHistory() async {
        guard let environment else { return }
        let model = environment.intelligenceIsland.model
        model.show(.history)
        await environment.intelligenceIsland.refreshHistory()
    }

    /// Continuous meeting end: generate follow-up suggestions and persist the
    /// take through the existing repository (the meeting engine already saved
    /// it). No suggestion state is stored in a second database.
    public func endMeetingWithIntelligenceSuggestions() async {
        guard let model = intelligenceModel else { return }
        await model.generateSuggestions()
    }

    public func askIntelligenceSuggestion(_ question: String) async {
        await intelligenceModel?.askSuggestion(question)
    }

    /// The SwiftUI content Agent 1 hosts for the live Island state.
    public func intelligenceContent(for slot: IntelligenceIslandSlot) -> AnyView? {
        environment?.intelligenceIsland.content(for: slot)
    }
}
