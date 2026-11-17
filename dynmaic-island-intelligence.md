# Clearly: Input + Stealth Backend Architecture

Scope: the backend that is MISSING. Everything else already exists (Reflection streaming, prompts, screen reading/OCR, Island bridge, history; see `docs/architecture/intelligence-backend-validation.md`). Do not rewrite it. Wrap it.

What is missing:

1. Global key bindings. Right Option = push-to-talk. Left Control = meeting start/stop.
2. Capture exclusion. The Island is visible to the user and excluded from what the other side receives in a Google Meet / Zoom / Teams share.
3. The permission + capability layer both of those depend on.
4. Wiring into the existing Island bridge.

---

## 1. Platform truth (read before writing any stealth code)

The earlier audit said "no supported public API." That is half right.

- There IS a public mechanism: `NSWindow.sharingType = .none`. It is the only one. Apple labels it legacy and does not promise it hides content from ScreenCaptureKit (SCK).
- Evidence is contradictory. Developer-forum and Electron/Tauri issue reports say SCK-based capture ignores it on macOS 15.x. More recent third-party tests on macOS 26.x report zero captured pixels in SCK, `screencapture`, and Meet-in-Chrome. Behavior depends on macOS build AND on which capture client / share mode is used.
- So: this can't be "implemented and done." It must be applied, verified at runtime on the actual machine, and degraded honestly when verification fails. That is the whole design.
- NO private APIs (CGS/SLS window tags etc.). They break across macOS releases and are not worth it.

What `.none` does NOT cover. All of these must be handled or documented, not ignored:

| Leak surface | Handling |
|---|---|
| Any other window the app creates (SwiftUI popover, Picker menu, `.help` tooltip, NSAlert, status item window) defaults to `.readOnly` | Enforce `.none` on every app-owned window (section 4). Build pickers/menus in-island as custom views. No native popovers/alerts. |
| SCK still lists the window (title, frame) in shareable-window lists, so it can appear in a "Window" picker | Empty title, accessory app, excluded from Windows menu. Documented as residual. |
| Dock icon, Cmd-Tab, Mission Control | `LSUIElement = true`, `.accessory` activation policy |
| Notification banners, sounds, Dock bounce | None. Never use `UNUserNotificationCenter` or sounds in-session. |
| Menu bar status item | If kept, set `statusItem.button?.window?.sharingType = .none`. Otherwise no status item. |
| HDMI capture cards, a phone pointed at the screen, display-level remote desktop | Not solvable in software. Documented. |
| Employer/proctoring software that enumerates processes/windows | Out of scope. Do not try to detect or evade it. |

---

## 2. Module map

```
Sources/Clearly/
  Input/
    HotkeyService.swift          CGEventTap (listen-only) -> RawKeyEvent stream
    GestureRecognizer.swift      pure state machine: RawKeyEvent -> KeyGesture (no OS deps, unit-tested)
  Stealth/
    StealthWindowController.swift  applies + enforces sharingType, level, collection behavior
    StealthVerifier.swift          SCK self-probe with positive control
    StealthStatus.swift            Verified / Failed / Unverified, persisted per macOS build
  Permissions/
    PermissionCenter.swift       Mic, Screen Recording, Input Monitoring: status, request, deep links
  Session/
    SessionCoordinator.swift     actor: gestures -> existing PTT / Meeting backend + Island state
  (existing, unchanged)          Reflection streaming, prompts, OCR, Island bridge, history
```

No Accessibility permission anywhere. Do not add it; it enlarges the permission surface for no gain.

---

## 3. Input: key bindings

### 3.1 Facts

- Key codes: Left Option 58, **Right Option 61**, **Left Control 59**, Right Control 62.
- Modifier presses arrive as `flagsChanged`. `.maskAlternate` is set if EITHER Option is held, so it cannot tell sides apart. Use the device-dependent bits in `event.flags.rawValue`: right Option `0x40` (NX_DEVICERALTKEYMASK), left Control `0x01` (NX_DEVICELCTLKEYMASK). Press vs release = that bit set vs clear.
- Needs **Input Monitoring** (`CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`). Listen-only tap, so it never delays or swallows user input.
- The trigger-key picker is deleted. Right Option is hardcoded. Migrate: drop any stored trigger-key preference on launch.

### 3.2 HotkeyService

```swift
let mask: CGEventMask =
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue)

let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                            options: .listenOnly, eventsOfInterest: mask,
                            callback: hotkeyCallback, userInfo: refcon)

func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                    refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let svc = Unmanaged<HotkeyService>.fromOpaque(refcon!).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        svc.reenable()
    case .flagsChanged:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let raw = event.flags.rawValue
        if code == 61      { svc.emit(raw & 0x40 != 0 ? .rightOptionDown : .rightOptionUp) }
        else if code == 59 { svc.emit(raw & 0x01 != 0 ? .leftControlDown : .leftControlUp) }
        else               { svc.emit(.interference) }   // any other modifier = not a lone press
    default:
        svc.emit(.interference)                          // keyDown / mouseDown
    }
    return Unmanaged.passUnretained(event)
}
```

Rules:

- Run the tap on a dedicated thread with its own `CFRunLoop`. The callback does O(1) work: push a small struct into an `AsyncStream` continuation and return. A slow callback makes macOS disable the tap.
- Re-enable on `tapDisabledByTimeout/UserInput`. Watchdog every 2s: `CGEvent.tapIsEnabled(tap:)`, recreate if dead. Recreate on `NSWorkspace.didWakeNotification`.
- Timestamps: `ProcessInfo.processInfo.systemUptime` (monotonic), never wall clock.
- Secure Event Input (password fields, some terminals) can starve taps. Behavior for modifier-only events is UNVERIFIED, so test it. Poll `IsSecureEventInputEnabled()` and surface "Hotkeys paused: secure input active" instead of failing silently.
- If `tapCreate` returns nil right after the user grants Input Monitoring, it may need a relaunch. UNVERIFIED, so test and handle with a "Restart to finish" state if true.

### 3.3 GestureRecognizer (pure, table-driven, unit-tested)

Constants live in one `GestureConfig`: `holdThreshold = 0.25s`, `ctrlTapMax = 0.5s`, `ctrlDebounce = 0.4s`, `maxListen = 120s`.

**Push-to-talk (Right Option only; Left Option and Right Control do nothing)**

| State | Event | Next | Emit |
|---|---|---|---|
| idle | rightOptionDown | pressed | `pttBegan` |
| pressed | interference | idle | `pttCancelled` |
| pressed | rightOptionUp, held >= 0.25s | idle | `pttSend` |
| pressed | rightOptionUp, held < 0.25s | latched | `pttLatched` |
| latched | rightOptionDown | latchedDown | none |
| latchedDown | rightOptionUp | idle | `pttSend` |
| latched / latchedDown | interference | unchanged | none |
| latched | 120s elapsed | idle | `pttSend` |

Why audio starts on press and not after the threshold: first words are not lost (keep a pre-roll buffer). Why `interference` cancels: Option+key types special characters (Option+E = accent). Without this, normal typing triggers the mic. On `pttCancelled`, discard the audio and do not send. Island visuals (waveform) appear only after ~120ms of clean hold to avoid flicker on Option+key.

**Meeting toggle (Left Control only)**

| State | Event | Next | Emit |
|---|---|---|---|
| idle | leftControlDown | ctrlPressed | none |
| ctrlPressed | interference | idle | none (Ctrl+click is a right-click, Ctrl+key is a shortcut) |
| ctrlPressed | leftControlUp, held < 0.5s and >= 0.4s since last toggle | idle | `meetingToggle` |
| ctrlPressed | leftControlUp otherwise | idle | none |

PTT and meeting are independent: PTT may fire during a live meeting.

---

## 4. Stealth

### 4.1 StealthWindowController

Island = `NSPanel`:

```swift
styleMask: [.borderless, .nonactivatingPanel]
isOpaque = false; backgroundColor = .clear; hidesOnDeactivate = false
title = ""; isExcludedFromWindowsMenu = true
level = .statusBar
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
sharingType = .none          // set BEFORE the first orderFront
```

App: `LSUIElement = true`, `NSApp.setActivationPolicy(.accessory)`.

**Invariant: the app owns zero capturable windows, ever.** Enforcement:

- A `WindowGuard` re-applies `sharingType = .none` to every window in `NSApp.windows` on: `NSWindow.didUpdateNotification`, screen-parameter change, active-space change, wake, and every Island show. It is idempotent and cheap.
- Debug builds `assert` the invariant after each state transition.
- SwiftUI/AppKit controls that create their own windows (popover, `Picker` menu, `.help`, NSAlert, NSMenu popups) are banned. Build the pickers, menus, tooltips, and confirmations as in-island views. This also matches the single-surface design.
- A user-facing toggle "Visible in screen share" flips `.none` <-> `.readOnly` for when the user wants to present the Island on purpose. Default: hidden.

### 4.2 Island must not read itself

For the existing screen-reading path, build the filter with the Island excluded explicitly and do not depend on `sharingType` for that:

```swift
SCContentFilter(display: display, excludingWindows: [islandSCWindow])
```

This is public and reliable. It prevents the OCR feedback loop regardless of what `sharingType` does on a given macOS.

### 4.3 StealthVerifier

Goal: prove, on this Mac and this macOS build, that the Island's pixels do not appear in a capture made the way a meeting app would make it.

Procedure (needs Screen Recording permission; requires `SCScreenshotManager`, macOS 14+; older = `Unverified`):

1. Precondition: no live meeting, not mid-answer. Never run while a meeting is live.
2. Show two probe rectangles, pure `#FF00FF`, ~32x32, 2 frames:
   - Probe A inside the Island (`sharingType = .none`).
   - **Positive control**: a tiny borderless window next to it with `sharingType = .readOnly`.
3. Capture with NO exclusions: `SCContentFilter(display:excludingWindows: [])`, `SCScreenshotManager.captureImage`, pixel size from the display scale factor. Display id from `NSScreen.deviceDescription["NSScreenNumber"]`.
4. Count probe-colored pixels inside each rect (convert coordinates: bottom-left origin to top-left, points to pixels).
5. Result:
   - control >= 90% matched AND probe A < 1% matched -> `Verified`
   - control missing -> `Unverified` (capture itself was invalid; a pass here would be a false positive)
   - probe A present -> `Failed`

Persist `{status, macOS build (sysctl kern.osversion), date, display config}`. Re-verify on: first launch after Screen Recording is granted, macOS build change, display configuration change, and manual "Verify" in Settings.

### 4.4 StealthPolicy (honest degradation)

| Status | Behavior |
|---|---|
| Verified | Settings > Privacy: "Hidden from screen capture on this Mac: verified on macOS <build>, <date>". |
| Unverified | Persistent badge in the island: "Hiding not verified". Functions normally. |
| Failed | Persistent badge: "Visible to screen share on this Mac. Do not rely on hiding." The user decides. |

Copy rules: never "undetectable", never "invisible to everything". The verifier tests the capture framework, not every client's path, so the claim is bounded by section 6.

---

## 5. Permissions: PermissionCenter

| Permission | Status | Request | Deep link |
|---|---|---|---|
| Input Monitoring | `CGPreflightListenEventAccess()` | `CGRequestListenEventAccess()` | `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` |
| Screen Recording | `CGPreflightScreenCaptureAccess()` | `CGRequestScreenCaptureAccess()` | `...?Privacy_ScreenCapture` |
| Microphone | `AVCaptureDevice.authorizationStatus(for: .audio)` | `AVCaptureDevice.requestAccess(for: .audio)` | `...?Privacy_Microphone` |

- Re-check all three on `NSApplication.didBecomeActiveNotification`.
- macOS (15+) periodically re-prompts to re-approve Screen Recording for apps that use it. Treat revocation at runtime as a normal state, not an error.
- Degrade per missing permission:
  - No Input Monitoring: hotkeys off, typed input still works, inline "Enable hotkeys" row.
  - No Screen Recording: no screen context, stealth `Unverified`, answers still work.
  - No Mic: no voice; typed input works.
- The Island shows permission state inline in Settings (existing plan). No blocking modal windows.

---

## 6. SessionCoordinator (wiring)

One `actor`. Owns session state `{idle, ptt, meetingLive}` with PTT allowed as an overlay during `meetingLive`.

| Gesture | State | Action |
|---|---|---|
| `pttBegan` | any | start mic capture w/ pre-roll; Island -> listening (after 120ms) |
| `pttCancelled` | ptt | discard audio; Island -> previous state |
| `pttLatched` | ptt | keep listening; Island shows latched indicator |
| `pttSend` | ptt | stop capture -> existing transcript cleanup -> screen capture (Island excluded) -> existing Reflection stream -> Island answer view; save to history |
| `meetingToggle` | idle | start meeting: transcription ON, rolling buffer, existing question-detector live |
| `meetingToggle` | meetingLive | end meeting: stop capture, generate 4-5 suggested questions, save to history, Island -> suggestions |

During a PTT utterance in a live meeting, suppress the auto question-detector for that utterance to prevent a double answer.

---

## 7. Build order

1. `GestureRecognizer` + `GestureConfig` + table-driven unit tests (no OS code).
2. `PermissionCenter`.
3. `HotkeyService` (tap, thread, watchdog, wake handling).
4. `SessionCoordinator` wiring into the existing bridge. Delete the trigger-key picker + migrate stored prefs.
5. `StealthWindowController` + `WindowGuard`. Replace every native popover/menu/alert with in-island views.
6. `StealthVerifier` + `StealthStatus` + badge UI.
7. Compatibility matrix (section 8, gate 6).

---

## 8. Acceptance gates (all need proof: screenshots + short screen recording)

1. **Gestures:** unit tests cover every table row, plus Option+E (cancel), tap-latch, 120s timeout, Ctrl+click (ignored), toggle debounce.
2. **Keys live:** hold Right Option -> listen -> release -> answer. Left Option does nothing. Right Control does nothing. Option+key still types special characters in another app with no mic activation. Build your own driver script (synthetic `CGEvent` posts) for repeatable runs; document if the driver needs extra permissions.
3. **Meeting:** Left Control toggles; same key ends; suggestions appear.
4. **Tap resilience:** kill-and-recover test. Force-disable the tap, confirm watchdog re-enables. Sleep/wake test.
5. **Verifier honesty:** (a) normal run -> result matches reality; (b) force the Island to `.readOnly` and confirm the verifier returns `Failed`; (c) block Screen Recording and confirm `Unverified`. A verifier that cannot fail is worthless.
6. **Window invariant:** open Settings, History, every in-island picker, and an error state; enumerate `NSApp.windows` and assert all are `.none`.
7. **End-to-end, real world:** two devices in the same Google Meet. Share from the Mac in each mode: Entire Screen, Window, Chrome Tab. The receiving device screenshots what it sees; the Mac screenshots its own view. Island visible on the Mac, absent on the receiver, in every mode. Record the results as a matrix in `docs/stealth-compatibility.md`: client (Meet/Chrome, Zoom, Teams) x share mode x macOS build x result. Anything that fails gets listed as a known leak, not hidden.

---

## 9. Hard NOs

- No private window-server APIs.
- No Accessibility permission.
- No spoofing process or app names, no hiding from Activity Monitor, no detecting or evading proctoring/monitoring software.
- No marketing or UI copy promising invisibility beyond what the compatibility matrix shows.
- No other trigger keys, no key picker, no extra global hotkeys.
- No native popovers, alerts, or menus (each creates an uncontrolled window).