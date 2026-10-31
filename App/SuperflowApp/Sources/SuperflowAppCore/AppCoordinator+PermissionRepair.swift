import Foundation
import SuperflowPorts

@MainActor
extension AppCoordinator {
    func repairKeyboardAccess() async {
        guard let environment else { return }
        let permissions = environment.permissionGate
        for permission in [Permission.inputMonitoring, .accessibility] {
            if await permissions.status(permission) != .granted {
                let status = await permissions.request(permission)
                if status != .granted {
                    menuBarController.publishError(
                        "\(permission.label) needs approval. If Superflow is missing, click + in System Settings and select the app highlighted in Finder."
                    )
                    await permissions.openSystemSettings(permission)
                    return
                }
            }
        }
        await environment.refreshFunctionKeySuppression(for: settings.dictationKey)
        if hotkeyTask == nil {
            await tryStartHotkeys()
        } else {
            menuBarController.publishError("")
        }
    }

    /// Dictation is useless without Accessibility: the paste is a synthetic
    /// key event, which the OS drops for an untrusted process. Ask once per
    /// launch and say what to click instead of letting a finished dictation
    /// look like the app ignored the owner.
    func requestAccessibilityForPaste() async {
        guard let environment, settings.onboardingComplete else { return }
        guard await environment.permissionGate.status(.accessibility) != .granted else { return }
        guard !didPromptAccessibility else { return }
        didPromptAccessibility = true
        _ = await environment.permissionGate.request(.accessibility)
        menuBarController.publishError(
            "Accessibility is off, so Superflow cannot paste. Turn Superflow on in System Settings → Privacy & Security → Accessibility. Your text is on the clipboard and will paste as soon as it is on."
        )
    }

    /// The grant landed while a transcript was waiting. Paste it now instead of
    /// making the owner repeat the dictation.
    func retryPendingPasteIfPossible() async {
        guard let environment else { return }
        guard await environment.permissionGate.status(.accessibility) == .granted else { return }
        guard let outcome = await environment.sessionEngine.retryPendingInsertion() else { return }
        switch outcome {
        case .pasted, .accessibility:
            menuBarController.publishError("")
            islandBridge?.pasteRecovered()
        case .clipboardOnly, .permissionRequired, .blockedSecureField:
            break
        }
    }
}
