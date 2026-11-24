import SuperflowDesignSystem
import SuperflowFeatureIntelligence
import SuperflowFeatureSettings
import SuperflowUIComponents
import SwiftUI

/// The main route is a working assistant and meeting library, not API settings.
struct IntelligenceWorkspaceRoute: View {
    let coordinator: AppCoordinator
    @ObservedObject var menu: MenuBarController
    @State private var configuration = false
    @State private var searchFocus = false

    var body: some View {
        if configuration {
            IntelligenceView(onBack: {
                coordinator.intelligenceModel?.reloadPreferences()
                configuration = false
            })
        } else {
            Page(title: "Intelligence", subtitle: "Ask, record, and revisit your conversations.") {
                if let model = coordinator.intelligenceModel {
                    SearchField(text: Binding(get: { model.historyQuery }, set: { model.historyQuery = $0 }),
                                prompt: "Search meetings", isFocused: $searchFocus)
                }
            } trailing: {
                AppButton("Configure", glyph: .settings, kind: .quiet) { configuration = true }
            } content: {
                if let error = menu.error, !error.isEmpty {
                    Text(error).appType(.caption).foregroundStyle(Tok.text2)
                }
                if let model = coordinator.intelligenceModel {
                    IntelligenceContent(model: model, compact: false,
                                        recording: menu.meetingState.isActive,
                                        onRecord: { coordinator.toggleIntelligenceRecording() })
                        .task(id: model.historyQuery) {
                            try? await Task.sleep(for: .milliseconds(180))
                            guard !Task.isCancelled else { return }
                            await model.loadHistory(query: model.historyQuery)
                        }
                        .task(id: menu.meetingState.isActive) {
                            if !menu.meetingState.isActive { await model.loadHistory(query: model.historyQuery) }
                        }
                } else {
                    EmptyState("Intelligence is unavailable.", message: "The app has not finished loading.")
                }
            }
        }
    }
}
