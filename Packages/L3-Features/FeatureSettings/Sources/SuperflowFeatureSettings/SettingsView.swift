import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, dictation, text, meetings, privacy, advanced

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// The row titles this tab owns. Search uses this list, and each tab gates
    /// its rows with the same string, so nothing can be searchable and invisible.
    var titles: [String] {
        switch self {
        case .general: GeneralTab.titles
        case .dictation: DictationTab.titles
        case .text: TextTab.titles
        case .meetings: MeetingsTab.titles
        case .privacy: PrivacyTab.titles
        case .advanced: AdvancedTab.titles
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var tab: SettingsTab = .general
    @State private var searchFocus = false
    @State private var showingNotices = false
    @Environment(DialogHost.self) private var dialogs

    public init(model: SettingsViewModel) {
        self.model = model
    }

    private var query: String {
        model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        Page(title: "Settings", subtitle: "Everything stays on this Mac.", width: Layout.narrow, clipContent: true) {
            SearchField(text: $model.searchQuery, prompt: "Search settings", isFocused: $searchFocus)
        } trailing: {
            if model.hasChanges {
                AppButton("Discard", kind: .quiet, height: ControlHeight.regular) {
                    model.revert()
                }
                AppButton("Save", kind: .primary, height: ControlHeight.regular) {
                    Task { await model.save() }
                }
            }
        } content: {
            if let error = model.error {
                NoticeBanner(error, tone: .rose, actionTitle: "Reload") {
                    Task { await model.load() }
                }
            }
            if !model.issues.isEmpty {
                NoticeBanner(model.issues.map(\.message).joined(separator: " "), tone: .rose)
            }
            if query.isEmpty {
                Segmented(selection: $tab,
                          items: SettingsTab.allCases.map { .init($0.title, value: $0) })
                tabContent(tab, query: "")
            } else {
                searchResults
            }
        }
        .task { await model.load() }
        .searchShortcut($searchFocus)
        .onChange(of: showingNotices) { _, show in
            guard show else { return }
            dialogs.present { noticesDialog }
            showingNotices = false
        }
        .toast(model.toast)
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = SettingsTab.allCases.filter { tab in
            tab.titles.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        if matches.isEmpty {
            EmptyState("No settings match.",
                       message: "Clear the search to see every tab.")
        } else {
            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(matches) { match in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionHeader(match.title)
                        tabContent(match, query: query)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: SettingsTab, query: String) -> some View {
        switch tab {
        case .general: GeneralTab(model: model, query: query)
        case .dictation: DictationTab(model: model, query: query)
        case .text: TextTab(model: model, query: query)
        case .meetings: MeetingsTab(model: model, query: query)
        case .privacy: PrivacyTab(model: model, query: query, showNotices: $showingNotices)
        case .advanced: AdvancedTab(model: model, query: query)
        }
    }

    private var noticesDialog: some View {
        InfoDialog(title: "Third-party notices") {
            Text(model.thirdPartyNotices)
                .appType(.caption)
                .foregroundStyle(Tok.text2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One card, one shared control column. Eight points of card padding plus the
/// twelve-point inner inset lands the text on the same 20pt the rest of the app uses.
struct SettingsCard<Content: View>: View {
    private let titles: [String]
    private let query: String
    private let content: Content

    init(titles: [String], query: String, @ViewBuilder content: () -> Content) {
        self.titles = titles
        self.query = query
        self.content = content()
    }

    private var visible: Bool {
        guard !query.isEmpty else { return true }
        return titles.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        if visible {
            Card(padding: Space.xs) {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, Space.sm)
            }
        }
    }
}

public struct OpenModelsKey: EnvironmentKey {
    public static let defaultValue: @MainActor () -> Void = {}
}
public extension EnvironmentValues {
    var openModels: @MainActor () -> Void {
        get { self[OpenModelsKey.self] }
        set { self[OpenModelsKey.self] = newValue }
    }
}
