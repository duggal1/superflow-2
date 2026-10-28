import SuperflowContextProfiles
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

/// The four profiles the app ships, plus the honest state for settings that no
/// profile describes. Selecting one writes only the fields a profile owns.
enum ContextProfileChoice: String, CaseIterable, Identifiable {
    case writing, chat, code, prompting, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .writing: "Writing"
        case .chat: "Chat"
        case .code: "Code"
        case .prompting: "Prompting"
        case .custom: "Custom"
        }
    }

    var profile: ContextProfile? {
        switch self {
        case .writing: .writing
        case .chat: .chat
        case .code: .code
        case .prompting: .prompting
        case .custom: nil
        }
    }

    var summary: String {
        guard let profile else { return "Changed by hand" }
        var parts = [profile.cleanupStyling, profile.cleanupStructure, profile.cleanupContext]
        if profile.codeSpeakEnabled { parts.append("Code Speak") }
        return parts.joined(separator: " · ")
    }

    static let builtIn: [ContextProfileChoice] = [.writing, .chat, .code, .prompting]

    static func matching(_ settings: AppSettings) -> ContextProfileChoice {
        builtIn.first { $0.profile?.matches(settings) == true } ?? .custom
    }
}

/// Presets above, the one detail knob below. A profile is a fill on the row,
/// never a second card, and the check is the only accent in the list.
struct ContextProfileCard: View {
    nonisolated static let titles = ["Context profile"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    private var active: ContextProfileChoice { ContextProfileChoice.matching(model.settings) }

    private var visible: Bool {
        guard !query.isEmpty else { return true }
        if Self.titles.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return true
        }
        if ContextProfileChoice.builtIn.contains(where: {
            $0.title.localizedCaseInsensitiveContains(query)
        }) {
            return true
        }
        return "Cleanup context".localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        if visible {
            Card(padding: Space.xs) {
                VStack(spacing: 0) {
                    Text("Context profile")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Tok.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Space.sm)
                        .padding(.bottom, Space.xxs)
                    ForEach(ContextProfileChoice.builtIn) { choice in
                        row(choice)
                    }
                    note
                    SettingRow(.cleanup, "Cleanup context", filter: query) {
                        Dropdown(selection: $model.settings.cleanupContext,
                                 options: Self.contextOptions,
                                 label: "Cleanup context")
                    }
                }
                .padding(.horizontal, Space.sm)
            }
        }
    }

    private func row(_ choice: ContextProfileChoice) -> some View {
        let isActive = choice == active
        return RowButton("\(choice.title) profile", height: 40, selected: isActive,
                         hoverFill: Tok.well) {
            guard let profile = choice.profile else { return }
            model.applyProfile(profile)
        } content: {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(choice.title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Tok.text)
                    Text(choice.summary)
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                if isActive {
                    Icon(.checkmark, size: 12, weight: .medium, tint: Tok.accent)
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }

    private var note: some View {
        Text(active == .custom
             ? "Custom. These settings were changed by hand."
             : "Sets styling, structure, context and Code Speak. Nothing else changes.")
            .font(Typography.secondary)
            .foregroundStyle(Tok.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.sm)
    }

    private static let contextOptions: [Dropdown<String>.Option] = [
        Dropdown.Option("General", value: "general"),
        Dropdown.Option("Chat", value: "chat"),
        Dropdown.Option("Code", value: "code"),
        Dropdown.Option("Prompt", value: "prompt"),
    ]
}
