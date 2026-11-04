import AppKit
import SuperflowDesignSystem
import SuperflowFeatureDashboard
import SuperflowFeatureDictionary
import SuperflowFeatureHistory
import SuperflowFeatureMeetings
import SuperflowFeatureOnboarding
import SuperflowFeatureSettings
import SuperflowFeatureShortcuts
import SuperflowIcons
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

/// The whole post-onboarding app: a custom `HStack` shell, no system split view,
/// no system toolbar. The sidebar is native blur; the detail pane paints the canvas.
public struct MainWindowRootView: View {
    @ObservedObject private var coordinator: AppCoordinator
    @ObservedObject private var windowController: MainWindowController
    @ObservedObject private var menuBar: MenuBarController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let retryStartup: (() -> Void)?
    @State private var menuHost = MenuHost()
    @State private var dialogHost = DialogHost()

    public init(coordinator: AppCoordinator, retryStartup: (() -> Void)? = nil) {
        self.retryStartup = retryStartup
        self.coordinator = coordinator
        self.windowController = coordinator.mainWindowController
        self.menuBar = coordinator.menuBarController
    }

    public var body: some View {
        Group {
            if let startupError = coordinator.startupError {
                StartupStatusView(message: startupError, retry: retryStartup)
                    .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
            } else if !coordinator.settings.onboardingComplete,
                      coordinator.isLoaded || !OnboardingCheckpoint.isComplete(),
                      let model = coordinator.onboardingModel {
                // The UserDefaults checkpoint decides the first frame, so a
                // finished setup never flashes onboarding while settings load.
                OnboardingView(model: model)
                    .frame(width: Layout.onboardingWidth, height: Layout.onboardingHeight)
                    .background(Tok.bg)
                    .background(WindowChrome(kind: .onboarding))
            } else {
                // The dashboard is the first frame. Launch work that can take
                // longer than a frame happens after it is already visible.
                mainWindow
            }
        }
        .preferredColorScheme(coordinator.themeStore.preferredColorScheme)
        .fontSmoothing()
        .focusEffectDisabled()
        .onAppear {
            // Connect as soon as the window exists so menu-bar and onboarding actions can
            // always bring it back, even before the menu-bar menu has ever been opened.
            coordinator.mainWindowController.connect { openWindow(id: "main") }
            coordinator.mainWindowController.didOpen()
        }
        .onDisappear { coordinator.mainWindowController.didClose() }
        .task {
            if let environment = coordinator.environment {
                await environment.audioArchive.setRetentionRepository(environment.transcripts)
            }
            await coordinator.launch()
        }
    }

    private var selection: AppSection {
        windowController.selection ?? .dashboard
    }

    private var route: Binding<AppSection> {
        Binding(get: { selection }, set: { windowController.selection = $0 })
    }

    private var mainWindow: some View {
        HStack(spacing: 0) {
            if windowController.sidebarVisible {
                MainSidebar(selection: route, status: engineStatus) {
                    let status = engineStatus
                    dialogHost.present {
                        SystemStatusDialog(status: status.label,
                                           speech: ModelProfile.byID(coordinator.settings.asrProfile).displayName,
                                           cleanupEnabled: coordinator.settings.cleanupEnabled,
                                           needsAttention: status == .noMicrophone || status == .noKeyboardAccess) {
                            open(status.fix)
                        }
                    }
                }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            ZStack {
                sectionContent
                    .id(selection)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // The canvas, edge to edge, under the traffic-light zone too.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Tok.bg)
        }
        .animation(reduceMotion ? nil : Motion.slide, value: windowController.sidebarVisible)
        .animation(reduceMotion ? nil : Motion.fade, value: selection)
        .ignoresSafeArea()
        .coordinateSpace(name: WindowSpace.name)
        .overlay { MenuLayer() }
        .overlay { DialogLayer() }
        .environment(menuHost)
        .environment(dialogHost)
        .environment(\.openModels, { windowController.show(.models) })
        .background(WindowChrome(kind: .main))
        .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        .tint(Tok.accent)
        .overlay {
            CommandPalette(model: coordinator.commandPaletteModel,
                           isPresented: Binding(
                            get: { coordinator.isCommandPalettePresented },
                            set: { if !$0 { coordinator.dismissCommandPalette() } }
                           ))
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .dashboard:
            if let model = coordinator.dashboardModel {
                DashboardView(model: model, openHistory: { windowController.selection = .history })
                    .task {
                        if let environment = coordinator.environment {
                            model.recent.configureRetry { url in
                                try await DashboardRetranscription.transcribe(url, environment: environment)
                            }
                        }
                    }
            }
        case .history:
            if let model = coordinator.historyModel { HistoryView(model: model) }
        case .knowledge, .dictionary, .shortcuts:
            if let terms = coordinator.dictionaryModel, let shortcuts = coordinator.shortcutsModel,
               let environment = coordinator.environment {
                KnowledgeView(
                    dictionary: terms, shortcuts: shortcuts,
                    learning: environment.learningEngine,
                    learningEnabled: Binding(
                        get: { coordinator.settings.learningEnabled },
                        set: { enabled in
                            Task { @MainActor in
                                var updated = coordinator.settings
                                updated.learningEnabled = enabled
                                if !enabled { updated.autoLearnEnabled = false }
                                await coordinator.applySettings(updated)
                                await environment.settingsStore.save(updated)
                            }
                        }),
                    autoLearnEnabled: Binding(
                        get: { coordinator.settings.autoLearnEnabled },
                        set: { enabled in
                            Task { @MainActor in
                                var updated = coordinator.settings
                                updated.autoLearnEnabled = enabled && updated.learningEnabled
                                await coordinator.applySettings(updated)
                                await environment.settingsStore.save(updated)
                            }
                        }),
                    onLearningChange: { await coordinator.refreshPipeline() }
                )
            }
        case .meetings:
            if let model = coordinator.meetingsModel { MeetingsView(model: model) }
        case .models:
            if let model = coordinator.modelsModel { ModelsView(vm: model) }
        case .intelligence:
            IntelligenceView()
        case .settings:
            if let model = coordinator.settingsModel { SettingsView(model: model) }
        }
    }

    // MARK: engine status

    private var engineStatus: EngineStatus {
        // Fn is handled by a global event tap, so without Input Monitoring the key
        // does nothing at all. Say which permission is missing instead of mapping
        // every error to the microphone pane.
        if let error = menuBar.error,
           error.localizedCaseInsensitiveContains("input monitoring")
            || error.localizedCaseInsensitiveContains("keyboard shortcut") {
            return .noKeyboardAccess
        }
        if let error = menuBar.error {
            let lower = error.lowercased()
            // Only an actual permission denial should send the owner to the
            // microphone privacy pane. Capture and model failures also mention
            // "microphone", but opening System Settings for them is misleading.
            if lower.contains("microphone"),
               (lower.contains("permission") || lower.contains("denied")
                || lower.contains("not authorized") || lower.contains("not granted")
                || lower.contains("access")) {
                return .noMicrophone
            }
        }
        switch menuBar.sessionState {
        case .warming, .recording, .finalizing, .inserting:
            // A warming session already owns the microphone, so it is listening
            // from the owner's point of view. Model loading is never surfaced.
            return .listening
        case .idle, .complete, .cancelled, .failed:
            return .ready
        }
    }

    private func open(_ fix: EngineFix) {
        switch fix {
        case .settings:
            windowController.show(.settings)
        case .microphone:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            if let url { NSWorkspace.shared.open(url) }
        case .keyboardAccess:
            Task { await coordinator.repairKeyboardAccess() }
        }
    }
}

private struct StartupStatusView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Superflow")
                .appType(.title)
                .foregroundStyle(Tok.text)
            Text(message)
                .appType(.body)
                .foregroundStyle(Tok.text2)
                .textSelection(.enabled)
                .frame(maxWidth: Space.proseMaxWidth, alignment: .leading)
            if let retry {
                AppButton("Try again", kind: .secondary, action: retry)
            }
        }
        .padding(Space.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Tok.bg)
    }
}
