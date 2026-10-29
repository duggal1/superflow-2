import Foundation
import SwiftUI

@MainActor
public final class AppCoordinatorOwner: ObservableObject {
    @Published public private(set) var coordinator: AppCoordinator
    private let supportDirectory: URL

    public init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
        coordinator = AppCoordinator(applicationSupportDirectory: supportDirectory)
    }

    public func retryStartup() {
        guard coordinator.environment == nil else { return }
        coordinator = AppCoordinator(applicationSupportDirectory: supportDirectory)
    }
}
