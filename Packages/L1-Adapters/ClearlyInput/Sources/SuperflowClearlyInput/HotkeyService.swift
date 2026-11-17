import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

public enum HotkeyServiceError: Error, Sendable, Equatable {
    /// The tap could not be created. Immediately after a fresh Input Monitoring
    /// grant this usually means the app must be relaunched.
    case tapUnavailable
}

/// Listen-only CGEventTap for the two fixed bindings.
///
/// It observes modifier flag changes and "any other key/click" only; it never
/// swallows an event, never installs a filtering tap, and never adds a second
/// global hotkey. All work in the tap callback is O(1): map and yield, then
/// return the event unchanged. A dedicated thread owns the tap's run loop so a
/// busy main thread cannot make macOS disable the tap.
public final class HotkeyService: @unchecked Sendable {

    public let events: AsyncStream<Clearly.RawEvent>
    private let continuation: AsyncStream<Clearly.RawEvent>.Continuation
    /// Emits true when Secure Event Input (password fields, some terminals)
    /// starves taps, false when it ends.
    public let secureInputUpdates: AsyncStream<Bool>
    private let secureContinuation: AsyncStream<Bool>.Continuation

    private let lock = NSLock()
    /// Serializes watchdog and sleep/wake recreations.
    private let recreateLock = NSLock()
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var exitSignal: DispatchSemaphore?
    private var watchdog: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var running = false
    private var securePaused = false
    private var securePausedAnnounced = false
    private var _needsRelaunch = false

    public init() {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
        (secureInputUpdates, secureContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    }

    deinit { stop() }

    public var isSecureInputPaused: Bool { lock.withLock { securePaused } }
    public var needsRelaunch: Bool { lock.withLock { _needsRelaunch } }

    // MARK: lifecycle

    public func start() throws {
        guard lock.withLock({ !running }) else { return }
        try installTapAndWorker()
        let paused = IsSecureEventInputEnabled()
        lock.withLock {
            securePaused = paused
            securePausedAnnounced = paused
            running = true
        }
        secureContinuation.yield(paused)
        installWakeObserver()
        startWatchdog()
    }

    public func stop() {
        lock.withLock { running = false }
        if let observer = lock.withLock({ () -> NSObjectProtocol? in
            let value = wakeObserver
            wakeObserver = nil
            return value
        }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        lock.withLock { watchdog?.cancel(); watchdog = nil }
        teardownTapAndWorker()
    }

    /// Creates the port and gives it a private run loop on a dedicated thread.
    private func installTapAndWorker() throws {
        guard let newTap = createTap() else {
            lock.withLock { _needsRelaunch = true }
            throw HotkeyServiceError.tapUnavailable
        }
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            lock.withLock { _needsRelaunch = true }
            throw HotkeyServiceError.tapUnavailable
        }
        lock.withLock {
            tap = newTap
            tapSource = newSource
            _needsRelaunch = false
        }
        CGEvent.tapEnable(tap: newTap, enable: true)

        let ready = DispatchSemaphore(value: 0)
        let exit = DispatchSemaphore(value: 0)
        lock.withLock { exitSignal = exit }
        let worker = Thread { [weak self] in
            guard let self else { ready.signal(); exit.signal(); return }
            let loop = CFRunLoopGetCurrent()
            let source = self.lock.withLock { () -> CFRunLoopSource? in
                self.runLoop = loop
                return self.tapSource
            }
            if let source { CFRunLoopAddSource(loop, source, .commonModes) }
            ready.signal()
            CFRunLoopRun()
            self.lock.withLock { self.runLoop = nil }
            exit.signal()
        }
        worker.name = "ClearlyInput.HotkeyService"
        worker.stackSize = 1 << 19
        lock.withLock { thread = worker }
        worker.start()
        _ = ready.wait(timeout: .now() + 3)
    }

    private func teardownTapAndWorker() {
        let old = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?, CFRunLoop?, DispatchSemaphore?) in
            let value = (tap, tapSource, runLoop, exitSignal)
            tap = nil
            tapSource = nil
            runLoop = nil
            thread = nil
            exitSignal = nil
            return value
        }
        if let loop = old.2 { CFRunLoopStop(loop) }
        // Wait for the worker to leave its run loop before invalidating the port.
        _ = old.3?.wait(timeout: .now() + 2)
        if let source = old.1, let loop = old.2 {
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        if let tap = old.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    /// Sleep/wake and a disabled tap both get a fresh port and a fresh run loop.
    private func recreate() {
        recreateLock.lock()
        defer { recreateLock.unlock() }
        guard lock.withLock({ running }) else { return }
        teardownTapAndWorker()
        do {
            try installTapAndWorker()
        } catch {
            lock.withLock { _needsRelaunch = true }
        }
    }

    // MARK: tap

    private func createTap() -> CFMachPort? {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        if let refcon {
            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            service.handle(type: type, event: event)
        }
        // Listen only: always pass the event through untouched.
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
            return
        case .flagsChanged:
            let raw = RawKeyEventMapper.map(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                                            flags: event.flags.rawValue,
                                            kind: .flagsChanged,
                                            timestamp: ProcessInfo.processInfo.systemUptime)
            emit(raw)
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            emit(Clearly.RawEvent(.interference, at: ProcessInfo.processInfo.systemUptime))
        default:
            break
        }
    }

    private func emit(_ event: Clearly.RawEvent) {
        let paused = lock.withLock { securePaused }
        if paused, !securePausedAnnounced {
            lock.withLock { securePausedAnnounced = true }
            secureContinuation.yield(true)
        }
        guard !paused else { return }
        continuation.yield(event)
    }

    private func reenable() {
        guard let tap = lock.withLock({ tap }) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: watchdog / wake / secure input

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ClearlyInput.watchdog"))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        timer.resume()
        lock.withLock { watchdog = timer }
    }

    private func watchdogTick() {
        let paused = IsSecureEventInputEnabled()
        let changed = lock.withLock { () -> Bool in
            let didChange = paused != securePaused
            securePaused = paused
            return didChange
        }
        if changed {
            if paused {
                // Cancel a half-finished hold instead of leaving the recognizer
                // waiting for a release the tap can no longer deliver.
                continuation.yield(Clearly.RawEvent(.interference, at: ProcessInfo.processInfo.systemUptime))
            } else {
                lock.withLock { securePausedAnnounced = false }
            }
            secureContinuation.yield(paused)
        }
        guard lock.withLock({ running }) else { return }
        let enabled = lock.withLock { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
        if enabled {
            reenable()   // idempotent; tapEnable refreshes the watchdog budget
        } else {
            recreate()
        }
    }

    private func installWakeObserver() {
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.recreate()
        }
        lock.withLock { wakeObserver = observer }
    }
}
