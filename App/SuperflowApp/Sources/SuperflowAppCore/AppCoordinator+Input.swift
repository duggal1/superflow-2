import Foundation
import SuperflowGestureKit
import SuperflowKernel
import SuperflowPorts

/// The input half of the coordinator: install the event tap, run key events through the pure
/// gesture recogniser, and react to permission changes while the app runs. Kept in its own file
/// so `AppCoordinator.swift` stays inside the repository's 400-line source limit.
@MainActor
extension AppCoordinator {
    func tryStartHotkeys() async {
        guard let environment, hotkeyTask == nil else { return }
        guard settings.onboardingComplete, menuBarController.recoveryReady else { return }
        guard await environment.permissionGate.status(.inputMonitoring) == .granted else { return }
        // Fn suppression is what keeps macOS from running its Globe action (Show Emoji & Symbols)
        // over dictation. Swallowing an event needs an active tap, so apply it before `start()`
        // creates the taps, otherwise the first tap is built listen-only.
        await environment.refreshFunctionKeySuppression()
        do {
            try await environment.hotkeySource.start()
            let events = environment.hotkeySource.events
            hotkeyTask = Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    await self.handleKeyEvent(event)
                }
            }
            gestureTimerTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .milliseconds(10))
                    } catch {
                        return
                    }
                    guard let self else { return }
                    await self.applyGestureActions(
                        self.gesture.tick(atNs: DispatchTime.now().uptimeNanoseconds)
                    )
                }
            }
        } catch {
            menuBarController.publishError("Keyboard shortcuts are unavailable. Check Input Monitoring in System Settings.")
        }
    }

    func observePermissionChanges(_ permissions: any PermissionGate) {
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            let updates = await permissions.updates()
            for await (permission, status) in updates {
                guard let self else { return }
                self.onboardingModel?.updatePermissionStatus(permission, status: status)
                switch permission {
                case .inputMonitoring:
                    if status == .granted {
                        await self.tryStartHotkeys()
                    } else if let environment = self.environment, self.hotkeyTask != nil {
                        await environment.hotkeySource.stop()
                        self.hotkeyTask?.cancel()
                        self.hotkeyTask = nil
                        self.gestureTimerTask?.cancel()
                        self.gestureTimerTask = nil
                        self.menuBarController.publishError(
                            "Keyboard shortcuts are unavailable. Check Input Monitoring in System Settings."
                        )
                    }
                case .accessibility:
                    // Gaining or losing Accessibility changes whether the lone Fn press can be
                    // swallowed at all, so re-apply it without needing a relaunch.
                    if self.hotkeyTask != nil {
                        await self.environment?.refreshFunctionKeySuppression()
                    }
                default:
                    break
                }
            }
        }
    }

    func handleKeyEvent(_ event: KeyEvent) async {
        // The dashboard's fn keycap follows the physical key, not the demo timer.
        if case .fnDown = event.kind { menuBarController.setFnHeld(true); dashboardModel?.setFnHeld(true) }
        if case .fnUp = event.kind { menuBarController.setFnHeld(false); dashboardModel?.setFnHeld(false) }
        await applyGestureActions(gesture.handle(event))
    }

    func applyGestureActions(_ actions: [GestureAction]) async {
        for action in actions {
            switch action {
            case .startSpeculative(.dictation):
                await menuBarController.startDictation()
            case .startSpeculative(.meeting):
                await menuBarController.startMeeting()
            case .holdBegan:
                break
            case .beginHandsFree:
                await menuBarController.beginHandsFreeDictation()
            case .latchMeeting:
                break
            case .submit(let kind):
                await menuBarController.stop(kind)
            case .cancel(let kind, let reason):
                await menuBarController.cancel(kind, cue: reason == .escape)
            }
        }
    }
}
