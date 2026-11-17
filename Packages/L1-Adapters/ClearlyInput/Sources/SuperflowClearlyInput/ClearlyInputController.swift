import Foundation

/// Process-wide owner of the listen-only tap and the gesture session. The app
/// coordinator calls `start`/`stop`; no stored properties have to be added to
/// `AppCoordinator` itself.
public final class ClearlyInputController: @unchecked Sendable {
    public static let shared = ClearlyInputController()

    private let hotkey = HotkeyService()
    private let lock = NSLock()
    private var coordinator: SessionCoordinator?
    private var eventTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var secureTask: Task<Void, Never>?
    private var running = false

    private init() {}

    public var isRunning: Bool { lock.withLock { running } }
    public var needsRelaunch: Bool { hotkey.needsRelaunch }
    public var isSecureInputPaused: Bool { hotkey.isSecureInputPaused }

    public func start(actions: IntelligenceSessionActions,
                      config: Clearly.Config = Clearly.Config()) throws {
        guard lock.withLock({ !running }) else { return }
        let coordinator = SessionCoordinator(actions: actions, config: config)
        try hotkey.start()
        let events = hotkey.events
        let secure = hotkey.secureInputUpdates
        lock.withLock {
            self.coordinator = coordinator
            self.running = true
        }
        eventTask = Task { for await event in events { await coordinator.handle(event) } }
        secureTask = Task {
            for await paused in secure { await coordinator.secureInputChanged(paused) }
        }
        tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await coordinator.tick()
            }
        }
    }

    public func stop() {
        let wasRunning = lock.withLock { () -> Bool in
            let value = running
            running = false
            coordinator = nil
            return value
        }
        guard wasRunning else { return }
        eventTask?.cancel()
        secureTask?.cancel()
        tickTask?.cancel()
        eventTask = nil
        secureTask = nil
        tickTask = nil
        hotkey.stop()
    }
}
