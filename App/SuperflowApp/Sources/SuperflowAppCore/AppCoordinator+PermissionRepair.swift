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
}
