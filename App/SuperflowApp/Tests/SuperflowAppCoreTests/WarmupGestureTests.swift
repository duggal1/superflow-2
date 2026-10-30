import AppKit
import Foundation
import SuperflowGestureKit
import SuperflowKernel
import SuperflowPorts
import XCTest
@testable import SuperflowAppCore

final class WarmupGestureTests: XCTestCase {
    @MainActor
    func testDoubleTapIsRecognizedWhileSessionActionsArePending() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = AppCoordinator(applicationSupportDirectory: directory)
        coordinator.menuBarController.setRecoveryReady(false)
        coordinator.gestureActionTask = Task { try? await Task.sleep(for: .milliseconds(200)) }
        await coordinator.handleKeyEvent(KeyEvent(kind: .fnDown, timestampNs: 0))
        await coordinator.handleKeyEvent(KeyEvent(kind: .fnUp, timestampNs: 80_000_000))
        await coordinator.handleKeyEvent(KeyEvent(kind: .fnDown, timestampNs: 200_000_000))
        XCTAssertEqual(coordinator.gesture.state, .handsFree)
        await coordinator.gestureActionTask?.value
    }

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
