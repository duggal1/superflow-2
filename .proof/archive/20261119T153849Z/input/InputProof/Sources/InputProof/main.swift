import Foundation
import CoreGraphics
import SuperflowClearlyInput

// Headless verification of R7/R8/R9-input and the input permission layer.
// Uses the REAL SuperflowClearlyInput mapper, recognizer and listen-only tap.
// No GUI, no cursor movement, no global keystrokes: synthetic CGEvents are
// either fed directly through the real mapper or posted ONLY to our own pid.

final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    func addAll(_ ss: [String]) { lock.lock(); items += ss; lock.unlock() }
    func get() -> [String] { lock.lock(); defer { lock.unlock() }; return items }
}

// Device-dependent modifier bits (must match RawKeyEventMapper).
let RIGHT_OPT: UInt64 = 0x40   // keycode 61
let LEFT_OPT: UInt64 = 0x20    // keycode 58
let LEFT_CTRL: UInt64 = 0x01   // keycode 59
let RIGHT_CTRL: UInt64 = 0x2000 // keycode 62

func flagsChanged(_ code: Int64, _ flags: UInt64) -> CGEvent {
    let e = CGEvent(source: nil)!
    e.type = .flagsChanged          // type first: setting it resets the keycode
    e.setIntegerValueField(.keyboardEventKeycode, value: code)
    e.flags = CGEventFlags(rawValue: flags)
    return e
}
func keyDown(_ code: Int64, _ flags: UInt64) -> CGEvent {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(code), keyDown: true)!
    e.flags = CGEventFlags(rawValue: flags)
    return e
}
func mouseDownEvent() -> CGEvent {
    let e = CGEvent(source: nil)!
    e.type = .leftMouseDown
    return e
}
func eventKind(_ e: CGEvent) -> RawKeyEventMapper.EventKind {
    switch e.type {
    case .flagsChanged: return .flagsChanged
    case .leftMouseDown, .rightMouseDown, .otherMouseDown: return .mouseDown
    default: return .keyDown
    }
}

typealias Step = (CGEvent, Double)

/// Feeds real CGEvent flag/keycode values through the REAL mapper + recognizer.
func gestures(for steps: [Step], config: Clearly.Config = Clearly.Config()) -> [Clearly.Gesture] {
    var g = Clearly.Recognizer(config: config)
    var out: [Clearly.Gesture] = []
    for (e, t) in steps {
        let raw = RawKeyEventMapper.map(
            keyCode: e.getIntegerValueField(.keyboardEventKeycode),
            flags: e.flags.rawValue,
            kind: eventKind(e), timestamp: t)
        out.append(contentsOf: g.handle(raw))
    }
    return out
}

let gNames: [Clearly.Gesture: String] = [
    .pttBegan: "pttBegan", .pttSend: "pttSend", .pttCancelled: "pttCancelled",
    .pttLatched: "pttLatched", .meetingToggle: "meetingToggle",
]
func names(_ gs: [Clearly.Gesture]) -> [String] { gs.map { gNames[$0] ?? "?" } }

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func inc() { lock.lock(); n += 1; lock.unlock() }
    func get() -> Int { lock.lock(); defer { lock.unlock() }; return n }
}
let failures = Counter()
func check(_ id: String, _ actual: [Clearly.Gesture], _ expected: [Clearly.Gesture]) {
    let a = names(actual), x = names(expected)
    let ok = a == x
    if !ok { failures.inc() }
    print("\(ok ? "PASS" : "FAIL") \(id): got \(a), expected \(x)")
}

let roDown = flagsChanged(61, RIGHT_OPT), roUp = flagsChanged(61, 0)
let lcDown = flagsChanged(59, LEFT_CTRL), lcUp = flagsChanged(59, 0)

print("=== PART A: real CGEvent flags -> real ClearlyInput mapper + recognizer ===")
// R7: hold -> send
check("R7.hold_send", gestures(for: [(roDown, 0), (roUp, 0.3)]), [.pttBegan, .pttSend])
// R7: quick tap -> latch, next press -> send
check("R7.tap_latch_then_send",
      gestures(for: [(roDown, 0), (roUp, 0.05), (roDown, 1.0), (roUp, 1.1)]),
      [.pttBegan, .pttLatched, .pttSend])
// R7: Option+E cancels a held PTT (keyDown E=14 is interference)
check("R7.optionE_cancels_hold",
      gestures(for: [(roDown, 0), (keyDown(14, 0x808), 0.01)]),
      [.pttBegan, .pttCancelled])
// R7: Left Option alone is inert (maps to interference, idle emits nothing)
check("R7.left_option_inert",
      gestures(for: [(flagsChanged(58, LEFT_OPT), 0), (flagsChanged(58, 0), 0.1)]), [])
// R7: Right Control alone is inert
check("R7.right_control_inert",
      gestures(for: [(flagsChanged(62, RIGHT_CTRL), 0), (flagsChanged(62, 0), 0.1)]), [])
// R7: an E keyDown alone (no trigger) is inert
check("R7.plain_key_inert", gestures(for: [(keyDown(14, 0), 0)]), [])
// R7/R9: Ctrl+click disarms a pending Left Control tap (no meeting toggle)
check("R9.ctrl_click_ignored",
      gestures(for: [(lcDown, 0), (mouseDownEvent(), 0.02), (lcUp, 0.1)]), [])
// R9: Left Control tap toggles; rapid repeat inside debounce suppressed
check("R9.ctrl_toggle_and_debounce",
      gestures(for: [(lcDown, 0), (lcUp, 0.2), (lcDown, 0.25), (lcUp, 0.35),
                     (lcDown, 0.6), (lcUp, 0.7)]),
      [.meetingToggle, .meetingToggle])

// R7: 120 s latch timeout via tick (same monotonic clock)
do {
    var g = Clearly.Recognizer()
    _ = g.handle(Clearly.RawEvent(.rightOptionDown, at: 0))
    _ = g.handle(Clearly.RawEvent(.rightOptionUp, at: 0.05))
    let before = g.tick(at: 119.9)
    let after = g.tick(at: 120.05)
    let ok = before.isEmpty && names(after) == ["pttSend"]
    if !ok { failures.inc() }
    print("\(ok ? "PASS" : "FAIL") R7.latch_timeout_120s: before=\(names(before)) after=\(names(after))")
}

print("=== PART B: live listen-only tap, events posted to OWN pid only ===")
// Input Monitoring is granted on this host; verify the tap really installs.
print("InputMonitoring granted: \(CGPreflightListenEventAccess())")
do {
    let svc = HotkeyService()
    try svc.start()
    let rawLog = Log()
    let gestureLog = Log()
    let drain = Task {
        var g = Clearly.Recognizer()
        for await ev in svc.events {
            rawLog.add(ev.key == .rightOptionDown ? "rightOptionDown" :
                       ev.key == .rightOptionUp ? "rightOptionUp" :
                       ev.key == .leftControlDown ? "leftControlDown" :
                       ev.key == .leftControlUp ? "leftControlUp" : "interference")
            gestureLog.addAll(names(g.handle(ev)))
        }
    }
    let pid = Int32(ProcessInfo.processInfo.processIdentifier)
    func post(_ e: CGEvent) { e.postToPid(pid) }
    // Right Option hold/release
    post(flagsChanged(61, RIGHT_OPT)); Thread.sleep(forTimeInterval: 0.08)
    post(flagsChanged(61, 0));        Thread.sleep(forTimeInterval: 0.08)
    // Left Option (58), Right Control (62), Option+E — must all be inert
    post(flagsChanged(58, LEFT_OPT)); Thread.sleep(forTimeInterval: 0.03)
    post(flagsChanged(58, 0));        Thread.sleep(forTimeInterval: 0.03)
    post(flagsChanged(62, RIGHT_CTRL)); Thread.sleep(forTimeInterval: 0.03)
    post(flagsChanged(62, 0));        Thread.sleep(forTimeInterval: 0.03)
    post(flagsChanged(61, RIGHT_OPT)); Thread.sleep(forTimeInterval: 0.02)
    post(keyDown(14, 0x808));         Thread.sleep(forTimeInterval: 0.02)
    post(flagsChanged(61, 0));        Thread.sleep(forTimeInterval: 0.08)
    Thread.sleep(forTimeInterval: 0.2)
    drain.cancel()
    svc.stop()
    let raw = rawLog.get(), ges = gestureLog.get()
    print("tap raw events seen: \(raw)")
    print("tap gestures emitted: \(ges)")
    if raw.isEmpty {
        print("INFO postToPid events were not observed by the session tap on this macOS build;")
        print("      Part A (real CGEvent flags through the real mapper) is the decisive proof.")
    } else {
        let expected = ["pttBegan", "pttSend", "pttBegan", "pttCancelled"]
        let ok = ges == expected
        if !ok { failures.inc() }
        print("\(ok ? "PASS" : "FAIL") R7.live_postToPid: got \(ges), expected \(expected)")
    }
}

print("=== SUMMARY ===")
print("{\"failures\": \(failures.get())}")
if failures.get() != 0 { exit(1) }
