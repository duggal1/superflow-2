import AppKit
import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowSessionEngine
import SuperflowTestKit
import SuperflowTextCleanup
import SuperflowTextPipeline
import XCTest
@testable import SuperflowAppCore

/// The fn double-tap must latch hands-free even when the first press is still
/// inside the model or microphone wait. These tests drive the controller with
/// a real `SessionEngine` over test doubles, so the wait is deterministic.
@MainActor
final class MenuBarHandsFreeTests: XCTestCase {
    private func makePipeline() -> TextPipeline {
        var settings = AppSettings.default
        settings.cleanupEnabled = true
        settings.harperEnabled = false
        let dependencies = TextPipelineDependencies(
            cleaner: CleanupService(cleaner: FakeTextCleaner(.identity))
        )
        return TextPipelineBuilder.make(settings: settings, dependencies: dependencies)
    }

    private func makeSession(recognizer: FakeSpeechRecognizer) -> SessionEngine {
        SessionEngine(audio: ScriptedAudioSource(samples: Array(repeating: 0.2, count: 16_000)),
                      recognizer: recognizer,
                      pipeline: makePipeline(),
                      repository: InMemoryRepository(),
                      journals: FakeJournalStore(),
                      inserter: RecordingInserter())
    }

    private func makeController(_ session: SessionEngine) -> (MenuBarController, FakeHotkeySource) {
        let hotkeys = FakeHotkeySource()
        let defaults = UserDefaults(suiteName: "MenuBarHandsFree-\(UUID().uuidString)")
        let controller = MenuBarController(session: session, meeting: nil, hotkeys: hotkeys,
                                           mainWindow: MainWindowController(defaults: defaults ?? .standard))
        return (controller, hotkeys)
    }

    private func waitForState(_ expected: SessionState, in session: SessionEngine,
                              timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await session.currentState == expected { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("session never reached \(expected)")
    }

    func testHandsFreeLatchesAnActiveRecording() async throws {
        let session = makeSession(recognizer: FakeSpeechRecognizer())
        let (controller, hotkeys) = makeController(session)
        _ = try await session.start(mode: .dictation)

        let latched = await controller.beginHandsFreeDictation()

        XCTAssertTrue(latched)
        let state = await session.currentState
        XCTAssertEqual(state, .recording(.handsFree))
        XCTAssertTrue(hotkeys.activeTap)
        await controller.stopDictation()
    }

    /// An explicit warm-up (onboarding or a settings change) holds `.warming`
    /// without a session. The double-tap waits for that load, then records.
    func testHandsFreeWaitsThroughExplicitWarming() async throws {
        let gate = AsyncGate()
        let recognizer = FakeSpeechRecognizer()
        await recognizer.setOnWarmUp { await gate.wait() }
        let session = makeSession(recognizer: recognizer)
        let (controller, hotkeys) = makeController(session)

        let warm = Task { await session.warmUp() }
        await waitForState(.warming, in: session)
        let handsFree = Task { await controller.beginHandsFreeDictation() }
        await gate.open()

        let latched = await handsFree.value
        _ = await warm.value
        XCTAssertTrue(latched)
        let state = await session.currentState
        XCTAssertEqual(state, .recording(.handsFree))
        XCTAssertTrue(hotkeys.activeTap)
        await controller.stopDictation()
    }

    /// A cold speculative start is already opening the microphone when the
    /// second tap lands. It must share that start and promote it, not race into
    /// "session already active".
    func testHandsFreeSharesASpeculativeStartDuringWarmUp() async throws {
        let gate = AsyncGate()
        let recognizer = FakeSpeechRecognizer()
        await recognizer.setOnWarmUp { await gate.wait() }
        let session = makeSession(recognizer: recognizer)
        let (controller, _) = makeController(session)

        let speculative = Task { await controller.startDictation(mode: .dictation) }
        await waitForState(.warming, in: session)
        let handsFree = Task { await controller.beginHandsFreeDictation() }
        await gate.open()

        let started = await speculative.value
        let latched = await handsFree.value
        XCTAssertTrue(started)
        XCTAssertTrue(latched)
        let state = await session.currentState
        XCTAssertEqual(state, .recording(.handsFree))
        await controller.stopDictation()
    }
}
