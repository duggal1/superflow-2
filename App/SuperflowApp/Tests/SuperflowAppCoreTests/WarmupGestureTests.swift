import AppKit
import Foundation
import SuperflowGestureKit
import SuperflowKernel
import XCTest
@testable import SuperflowAppCore

final class WarmupGestureTests: XCTestCase {
    @MainActor
    func testRepeatedFnAttemptsWhileLoadingReturnIslandToIdle() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("superflow-warmup-gesture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = AppCoordinator(applicationSupportDirectory: directory)
        let island = try XCTUnwrap(coordinator.islandController?.model)
        coordinator.menuBarController.setRecoveryReady(false)
        for _ in 0..<25 {
            await coordinator.applyGestureActions([.startSpeculative(.dictation), .submit(.dictation)])
        }
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(island.phase, .idle)
    }
}
