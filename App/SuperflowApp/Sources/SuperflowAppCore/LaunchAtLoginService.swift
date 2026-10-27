import ServiceManagement
import SuperflowPorts

@MainActor
public final class LaunchAtLoginService: LaunchAtLoginController {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public func isEnabled() async -> Bool {
        service.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            try service.register()
        } else {
            try await service.unregister()
        }
    }
}
