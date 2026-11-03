import AppKit
import Foundation
import SuperflowGestureKit
import SuperflowHotkeyEngine
import SuperflowKernel
import SuperflowPorts
import SuperflowTestKit
import XCTest
@testable import SuperflowAppCore

final class WarmupGestureTests: XCTestCase {
    @MainActor
    func testIntelligenceTriggerOpensMeetingsWithoutStartingADictationGesture() async {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = AppCoordinator(applicationSupportDirectory: directory)
        coordinator.menuBarController.setRecoveryReady(false)
        await coordinator.handleKeyEvent(KeyEvent(kind: .intelligenceDown, timestampNs: 0))
        XCTAssertEqual(coordinator.mainWindowController.selection, .meetings)
        for _ in 0..<100 where coordinator.isStartingIntelligenceMeeting {
            await Task.yield()
        }
        XCTAssertFalse(coordinator.isStartingIntelligenceMeeting)
        XCTAssertNotEqual(AppSection.intelligence.icon, AppSection.meetings.icon)
        XCTAssertEqual(coordinator.gesture.state, .idle)
    }

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
    func testGlobeCompanionsAndCommandDoubleTapWhileStartIsPending() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = AppCoordinator(applicationSupportDirectory: directory)
        coordinator.menuBarController.setRecoveryReady(false)
        coordinator.gestureActionTask = Task { try? await Task.sleep(for: .milliseconds(200)) }
        let cases: [(KeyEvent.Kind, KeyEvent.Kind, GestureState)] = [
            (.fnDown, .fnUp, .handsFree), (.rightCmdDown, .rightCmdUp, .meetingLatched)
        ]
        for (down, up, expected) in cases {
            coordinator.gesture = GestureRecognizer()
            await coordinator.handleKeyEvent(KeyEvent(kind: down, timestampNs: 0))
            await coordinator.handleKeyEvent(KeyEvent(kind: up, timestampNs: 80_000_000))
            let code = down == .fnDown ? KeyCode.globe : KeyCode.rightCommand
            if let companion = KeyEventMapper.keyDown(keyCode: code, timestampNs: 81_000_000) {
                await coordinator.handleKeyEvent(companion)
            }
            await coordinator.handleKeyEvent(KeyEvent(kind: down, timestampNs: 200_000_000))
            XCTAssertEqual(coordinator.gesture.state, expected)
        }
        await coordinator.gestureActionTask?.value
    }

    @MainActor
    func testRapidRetapsAndEscapeDoNotAccumulateStaleStarts() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = AppCoordinator(applicationSupportDirectory: directory)
        let gate = AsyncGate()
        coordinator.gestureActionTask = Task { await gate.wait() }
        let edges: [(KeyEvent.Kind, Int)] = [(.fnDown, 0), (.fnUp, 80), (.fnDown, 200), (.fnUp, 250), (.fnDown, 400)]
        for (kind, time) in edges {
            await coordinator.handleKeyEvent(KeyEvent(kind: kind, timestampNs: UInt64(time) * 1_000_000))
        }
        XCTAssertTrue(coordinator.gestureIsFinishing)
        for index in 0..<100 {
            await coordinator.handleKeyEvent(KeyEvent(kind: .fnDown, timestampNs: UInt64(index + 500) * 1_000_000))
            await coordinator.handleKeyEvent(KeyEvent(kind: .escape, timestampNs: UInt64(index + 501) * 1_000_000))
        }
        XCTAssertEqual(coordinator.gesture.state, .idle)
        XCTAssertTrue(coordinator.gestureCancelPending)
        await gate.open()
        await coordinator.gestureActionTask?.value
        XCTAssertFalse(coordinator.gestureIsFinishing)
        XCTAssertFalse(coordinator.gestureCancelPending)
        await coordinator.handleKeyEvent(KeyEvent(kind: .fnDown, timestampNs: 2_000_000_000))
        XCTAssertEqual(coordinator.gesture.state, .armed)
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
