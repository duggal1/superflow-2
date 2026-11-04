import AppKit
import Foundation
import SuperflowIcons
import SwiftUI

public enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard
    case history
    case knowledge
    // Kept only so existing persisted routes still decode without data loss.
    case dictionary
    case shortcuts
    case meetings
    case models
    case intelligence
    case settings

    public static let allCases: [AppSection] = [
        .dashboard, .history, .knowledge, .meetings, .models, .intelligence, .settings,
    ]
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .history: "History"
        case .knowledge, .dictionary, .shortcuts: "Knowledge"
        case .meetings: "Meetings"
        case .models: "Models"
        case .intelligence: "Intelligence"
        case .settings: "Settings"
        }
    }

    /// Apple symbols only; the sidebar concept matches the page.
    public var icon: Icon {
        switch self {
        case .dashboard: .dashboard
        case .history: .history
        case .knowledge, .dictionary, .shortcuts: .dictionary
        case .meetings: .meetings
        case .models: .models
        case .intelligence: .intelligence
        case .settings: .settings
        }
    }
}

@MainActor
public final class MainWindowController: ObservableObject {
    @Published public var selection: AppSection? {
        didSet {
            if let selection { defaults.set(selection.rawValue, forKey: Self.selectionKey) }
        }
    }

    /// The custom shell owns the sidebar, so the menu command toggles this.
    @Published public var sidebarVisible = true

    private static let selectionKey = "main-window.selection"
    private let defaults: UserDefaults
    private var openWindow: (@MainActor () -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.selectionKey)
        let restored = raw.flatMap(AppSection.init(rawValue:)) ?? .dashboard
        selection = restored == .dictionary || restored == .shortcuts ? .knowledge : restored
    }

    public func connect(openWindow: @escaping @MainActor () -> Void) {
        self.openWindow = openWindow
    }

    public func toggleSidebar() {
        sidebarVisible.toggle()
    }

    public func show(_ section: AppSection? = nil) {
        if let section {
            selection = section == .dictionary || section == .shortcuts ? .knowledge : section
        }
        NSApp.setActivationPolicy(.regular)
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func didOpen() {
        NSApp.setActivationPolicy(.regular)
        // Presenting a scene is not the same as showing it: SwiftUI can create the window behind
        // the current app, which reads as "nothing launched". Order it front whenever it appears.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    public func didClose() {
        NSApp.setActivationPolicy(.accessory)
    }
}
