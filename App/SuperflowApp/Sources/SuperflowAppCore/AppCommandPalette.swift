import SuperflowIcons
import SuperflowUIComponents

@MainActor
enum AppCommandPalette {
    static func make(onSelectSection: @escaping @MainActor (AppSection) -> Void,
                     onToggleDictation: @escaping @MainActor () -> Void,
                     onToggleMeeting: @escaping @MainActor () -> Void,
                     onQuit: @escaping @MainActor () -> Void) -> CommandPaletteModel {
        let sections = AppSection.allCases.map { section in
            CommandItem(id: "section.\(section.id)", title: "Go to \(section.title)",
                        icon: icon(for: section)) {
                onSelectSection(section)
            }
        }
        return CommandPaletteModel(items: sections + [
            CommandItem(id: "dictation.toggle", title: "Start or stop dictation",
                        subtitle: "Toggle microphone dictation", icon: .mic,
                        shortcut: "⌘⇧D", action: onToggleDictation),
            CommandItem(id: "meeting.toggle", title: "Start or stop meeting",
                        subtitle: "Toggle meeting capture", icon: .meetings, action: onToggleMeeting),
            CommandItem(id: "app.quit", title: "Quit Superflow", icon: .close,
                        shortcut: "⌘Q", action: onQuit),
        ])
    }

    private static func icon(for section: AppSection) -> Icon {
        switch section {
        case .dashboard: .dashboard
        case .history: .history
        case .dictionary: .dictionary
        case .shortcuts: .shortcuts
        case .meetings: .meetings
        case .models: .models
        case .settings: .settings
        }
    }
}

@MainActor
public extension AppCoordinator {
    func showCommandPalette() {
        mainWindowController.show()
        commandPaletteModel.reset()
        isCommandPalettePresented = true
    }

    func dismissCommandPalette() {
        isCommandPalettePresented = false
    }
}
