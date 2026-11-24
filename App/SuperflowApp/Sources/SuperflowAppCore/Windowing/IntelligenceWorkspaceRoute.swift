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

    var body: some View {
        if configuration {
            IntelligenceView(onBack: { configuration = false })
        } else {
            Page(title: "Intelligence", subtitle: "Ask, record, and revisit your conversations.") {
                EmptyView()
            } trailing: {
                AppButton("Configure", glyph: .settings, kind: .quiet) { configuration = true }
            } content: {
                if let model = coordinator.intelligenceModel {
                    IntelligenceContent(model: model, compact: false,
                                        recording: menu.meetingState.isActive,
                                        onRecord: { coordinator.toggleIntelligenceRecording() })
                } else {
                    EmptyState("Intelligence is unavailable.", message: "The app has not finished loading.")
                }
            }
        }
    }
}
