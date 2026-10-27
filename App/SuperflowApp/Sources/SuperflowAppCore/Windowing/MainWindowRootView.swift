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
    @State private var menuHost = MenuHost()

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.windowController = coordinator.mainWindowController
        self.menuBar = coordinator.menuBarController
    }

    public var body: some View {
        Group {
            if !coordinator.isLoaded {
                StartupStatusView(message: "Opening your local library…")
                    .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
            } else if let startupError = coordinator.startupError {
                StartupStatusView(message: startupError)
                    .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
            } else if !coordinator.settings.onboardingComplete,
                      let model = coordinator.onboardingModel {
                OnboardingView(model: model)
                    .frame(width: Layout.onboardingWidth, height: Layout.onboardingHeight)
                    .background(Tok.bg)
                    .background(WindowChrome(kind: .onboarding))
            } else {
                mainWindow
            }
        }
        .preferredColorScheme(coordinator.themeStore.preferredColorScheme)
        .onAppear {
            // Connect as soon as the window exists so menu-bar and onboarding actions can
            // always bring it back, even before the menu-bar menu has ever been opened.
            coordinator.mainWindowController.connect { openWindow(id: "main") }
            coordinator.mainWindowController.didOpen()
        }
        .onDisappear { coordinator.mainWindowController.didClose() }
        .task { await coordinator.launch() }
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
                MainSidebar(selection: route, status: engineStatus) { open(engineStatus.fix) }
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
        .environment(menuHost)
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
            if let model = coordinator.dashboardModel { DashboardView(model: model) }
        case .history:
            if let model = coordinator.historyModel { HistoryView(model: model) }
        case .dictionary:
            if let model = coordinator.dictionaryModel { DictionaryView(model: model) }
        case .shortcuts:
            if let model = coordinator.shortcutsModel { ShortcutsView(model: model) }
        case .meetings:
            if let model = coordinator.meetingsModel { MeetingsView(model: model) }
        case .settings:
            if let model = coordinator.settingsModel { SettingsView(model: model) }
        }
    }

    // MARK: engine status

    private var engineStatus: EngineStatus {
        if let error = menuBar.error,
           error.localizedCaseInsensitiveContains("microphone")
            || error.localizedCaseInsensitiveContains("input monitoring") {
            return .noMicrophone
        }
        switch menuBar.sessionState {
        case .warming:
            return .warming
        case .recording, .finalizing, .inserting:
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
        }
    }
}

// MARK: - Sidebar

/// Full height, flush left, 220 wide, native blur. The first row starts at y = 52
/// so it never meets the traffic lights. One fixed icon column, one colour for
/// icon and text, one neutral capsule that slides between rows.
private struct MainSidebar: View {
    @Binding var selection: AppSection
    let status: EngineStatus
    let onStatus: () -> Void
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 0) {
            WindowDragArea()
                .frame(height: Layout.bar)

            VStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    SidebarRow(section: section,
                               isSelected: selection == section,
                               pill: pill) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, Space.sm)

            Spacer(minLength: 0)

            SidebarStatus(status: status, action: onStatus)
                .padding(.horizontal, Space.sm)
                .padding(.bottom, Space.md)
        }
        .frame(width: Layout.sidebar)
        .frame(maxHeight: .infinity)
        .background { SidebarBackdrop() }
        .animation(Motion.slide, value: selection)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let pill: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(section.icon, size: 14, tint: Tok.text)
                    .frame(width: 20, height: 20)
                Text(section.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Tok.text)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Tok.washStrong)
                        .matchedGeometryEffect(id: "pill", in: pill)
                } else if hover {
                    Capsule().fill(Tok.wash)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : (hover ? Motion.hoverIn : Motion.hoverOut), value: hover)
        .clickable()
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.\(section.rawValue)")
    }
}

/// 6pt dot plus one word. The state source is unchanged; only the view is new.
private struct SidebarStatus: View {
    let status: EngineStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                DotView(status.tone)
                Text(status.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Tok.text2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .clickable()
        .help(status.label)
        .accessibilityLabel("Engine status: \(status.label)")
    }
}

/// `NSVisualEffectView` adapts to dark and light by itself. It needs the window to
/// be non-opaque to see the desktop, which `WindowChrome(.main)` guarantees.
private struct SidebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Status vocabulary

private enum EngineFix {
    case settings, microphone
}

private enum EngineStatus {
    case ready, warming, listening, noMicrophone

    var label: String {
        switch self {
        case .ready: "Ready"
        case .warming: "Warming up"
        case .listening: "Listening"
        case .noMicrophone: "No microphone access"
        }
    }

    var tone: DotTone {
        switch self {
        case .ready: .green
        case .warming, .listening: .orange
        case .noMicrophone: .rose
        }
    }

    var fix: EngineFix {
        switch self {
        case .noMicrophone: .microphone
        case .ready, .warming, .listening: .settings
        }
    }
}

private struct StartupStatusView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Superflow")
                .font(Typography.title)
                .foregroundStyle(Tok.text)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Tok.text2)
                .textSelection(.enabled)
                .frame(maxWidth: Space.proseMaxWidth, alignment: .leading)
        }
        .padding(Space.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Tok.bg)
    }
}
