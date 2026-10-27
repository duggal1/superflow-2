import SwiftUI

public struct MenuBarContentView: View {
    @ObservedObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let menu = coordinator.menuBarController
        Group {
            Button("Open Superflow") {
                coordinator.mainWindowController.show()
            }
            Divider()
            Button(menu.dictationTitle) {
                Task { await menu.toggleDictation() }
            }
            .disabled(!coordinator.isLoaded || (!menu.sessionState.isActive && !menu.canStartDictation))
            Button(menu.meetingTitle) {
                Task {
                    if menu.meetingState.isActive {
                        await menu.stopMeeting()
                    } else {
                        await menu.startMeeting()
                    }
                }
            }
            .disabled(!coordinator.isLoaded || (!menu.meetingState.isActive && !menu.canStartMeeting))
            Divider()
            Button("Settings") {
                coordinator.mainWindowController.show(.settings)
            }
            if let error = menu.error {
                Text(error)
                    .foregroundStyle(.secondary)
            }
            if let notice = coordinator.recoveryNotice {
                Text(notice)
                    .foregroundStyle(.secondary)
                if coordinator.recoveredTranscript != nil {
                    Button("Copy recovered text") {
                        coordinator.copyRecoveredTranscript()
                    }
                }
            }
            Divider()
            Button("Quit Superflow") {
                Task { await menu.quit() }
            }
        }
        .onAppear {
            coordinator.mainWindowController.connect {
                openWindow(id: "main")
            }
            Task { await coordinator.launch() }
        }
    }
}
