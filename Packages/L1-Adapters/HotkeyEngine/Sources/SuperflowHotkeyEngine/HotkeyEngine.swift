import AppKit
import CoreGraphics
import Foundation
import SuperflowKernel
import SuperflowPorts

/// Two taps, as described in PLAN.md: a listen-only tap for Fn/Right Command,
/// and a default tap installed only while recording so Enter and Escape can be
/// swallowed. Both are rebuilt after wake and re-enabled after timeouts.
public final class HotkeyEngine: HotkeySource, @unchecked Sendable {
    public let events: AsyncStream<KeyEvent>

    private let continuation: AsyncStream<KeyEvent>.Continuation
    private let lock = NSLock()
    private var passiveTap: CFMachPort?
    private var passiveSource: CFRunLoopSource?
    private var activeTap: CFMachPort?
    private var activeSource: CFRunLoopSource?
    private var wantsActive = false
    /// When true the passive tap is installed as an active tap so the lone Fn press can be
    /// swallowed before macOS runs its Globe action. Requires Accessibility.
    private var suppressFn = false
    private var lifecycle = HotkeyLifecycle()
    private var wakeObserver: NSObjectProtocol?
    private var healthTimer: DispatchSourceTimer?

    public init() {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    deinit {
        removeTaps()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        healthTimer?.cancel()
    }

    public func start() async throws {
        let shouldInstall = lock.withLock { lifecycle.beginStart() }
        if !shouldInstall { return }
        guard installPassiveTap() else {
            lock.withLock { lifecycle.startFailed() }
            throw SuperflowError.permissionDenied(Permission.inputMonitoring.label)
        }
        if lock.withLock({ wantsActive }) { installActiveTap() }
        observeWake()
        startHealthTimer()
    }

    public func stop() async {
        let shouldRemove = lock.withLock { lifecycle.beginStop() }
        guard shouldRemove else { return }
        removeTaps()
        if let observer = lock.withLock({ let value = wakeObserver; wakeObserver = nil; return value }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        healthTimer?.cancel()
        healthTimer = nil
        // The event stream deliberately stays open: Input Monitoring can be
        // revoked and re-granted while the app runs, and `events` is a stable
        // property on the port. Finishing it here would make every restart a
        // silent no-op for the coordinator's consumer task.
    }

    public func setActiveTap(_ on: Bool) async {
        lock.withLock { wantsActive = on }
        guard lock.withLock({ lifecycle.isRunning }) else { return }
        if on {
            if lock.withLock({ activeTap == nil }) { installActiveTap() }
        } else {
            removeActiveTap()
        }
    }

    /// Takes ownership of the lone Fn press. Swallowing an event is only possible from an active
    /// tap, which needs Accessibility; without it the system's Globe action still fires and the
    /// app simply keeps observing Fn. Reinstalls the taps so the new options take effect.
    public func setFnSuppression(_ on: Bool) async {
        let changed = lock.withLock { () -> Bool in
            guard suppressFn != on else { return false }
            suppressFn = on
            return true
        }
        guard changed, lock.withLock({ lifecycle.isRunning }) else { return }
        removeTaps()
        _ = installPassiveTap()
        if lock.withLock({ wantsActive }) { installActiveTap() }
    }

    // MARK: taps

    private func installPassiveTap() -> Bool {
        let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
            | CGEventMask(1) << CGEventType.keyDown.rawValue
        // A listen-only tap can observe Fn but can never take it from the system, which is exactly
        // why the Globe/Fn key still opened the emoji picker. With Accessibility the tap is
        // installed active so the lone Fn press can be swallowed; if that fails (no Accessibility)
        // we fall back to listening, so hotkeys keep working and only suppression is lost.
        let wantsSwallow = lock.withLock { suppressFn }
        var tap = makePassiveTap(mask: mask, options: wantsSwallow ? .defaultTap : .listenOnly)
        if tap == nil, wantsSwallow { tap = makePassiveTap(mask: mask, options: .listenOnly) }
        guard let tap else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.withLock {
            passiveTap = tap
            passiveSource = source
        }
        return true
    }

    private func makePassiveTap(mask: CGEventMask, options: CGEventTapOptions) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: Self.passiveCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
    }

    private func installActiveTap() {
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.activeCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.withLock {
            activeTap = tap
            activeSource = source
        }
    }

    private func removeActiveTap() {
        let state = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let value = (activeTap, activeSource)
            activeTap = nil
            activeSource = nil
            return value
        }
        if let tap = state.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = state.1 {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func removeTaps() {
        removeActiveTap()
        let state = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let value = (passiveTap, passiveSource)
            passiveTap = nil
            passiveSource = nil
            return value
        }
        if let tap = state.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = state.1 {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func reinstallAfterWake() {
        guard lock.withLock({ lifecycle.isRunning }) else { return }
        removeTaps()
        _ = installPassiveTap()
        if lock.withLock({ wantsActive }) { installActiveTap() }
    }

    // MARK: callbacks

    private static let passiveCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let engine = Unmanaged<HotkeyEngine>.fromOpaque(userInfo).takeUnretainedValue()
        return engine.handlePassive(proxy: proxy, type: type, event: event)
    }

    private static let activeCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let engine = Unmanaged<HotkeyEngine>.fromOpaque(userInfo).takeUnretainedValue()
        return engine.handleActive(proxy: proxy, type: type, event: event)
    }

    private func handlePassive(proxy _: CGEventTapProxy, type: CGEventType,
                               event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ passiveTap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        let timestamp = event.timestamp
        switch type {
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if let mapped = KeyEventMapper.flagsChanged(keyCode: keyCode, flags: event.flags,
                                                         timestampNs: timestamp) {
                continuation.yield(mapped)
                // Drop only the Fn modifier change so macOS cannot run its Globe action (Show
                // Emoji & Symbols) underneath us. Key events are untouched, so Fn plus a function
                // key or an arrow still delivers the real key: the system is not hijacked, only
                // the emoji binding is suppressed while Superflow runs.
                if mapped.kind == .fnDown || mapped.kind == .fnUp {
                    if lock.withLock({ suppressFn }) { return nil }
                }
            }
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let active = lock.withLock { activeTap != nil }
            if active, keyCode == KeyCode.enter || keyCode == KeyCode.escape {
                return Unmanaged.passUnretained(event)
            }
            continuation.yield(KeyEventMapper.keyDown(keyCode: keyCode, timestampNs: timestamp))
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleActive(proxy _: CGEventTapProxy, type: CGEventType,
                              event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ activeTap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == KeyCode.enter || keyCode == KeyCode.escape else {
            return Unmanaged.passUnretained(event)
        }
        continuation.yield(KeyEventMapper.keyDown(keyCode: keyCode, timestampNs: event.timestamp))
        return nil
    }

    // MARK: lifecycle

    private func observeWake() {
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reinstallAfterWake()
        }
        lock.withLock { wakeObserver = observer }
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let taps = self.lock.withLock { [self.passiveTap, self.activeTap].compactMap { $0 } }
            for tap in taps where !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        timer.resume()
        lock.withLock { healthTimer = timer }
    }
}
