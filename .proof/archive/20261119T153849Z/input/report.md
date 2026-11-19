# Agent 2 — ClearlyInput (fixed key bindings) report

## What was implemented

- Right Option is the only push-to-talk trigger: press starts listening,
  release after 250 ms sends, a tap under 250 ms latches and the next
  press-and-release sends. Any other key/click cancels a live hold (so
  Option+E still types a special character). Left Option and Right Control
  emit nothing on their own.
- Left Control tap toggles the continuous meeting, with a 0.4 s debounce;
  holds of 0.5 s or more and Ctrl+click are ignored.
- The trigger-key picker is gone from Intelligence settings and the stored
  `intelligence.trigger` preference is cleared on every launch/restart.
- Input runs on a listen-only CGEventTap with a dedicated run loop thread,
  device-dependent modifier bits (`0x40` right Option, `0x01` left Control),
  a 2 s watchdog, sleep/wake recreation, monotonic timestamps, and Secure
  Event Input pause state. No Accessibility permission and no other global
  hotkey were added.
- PermissionCenter covers Input Monitoring, Screen Recording and Microphone
  with status/request/deep links and recheck on activation.
- SessionCoordinator is an actor that drives the existing bridge through
  injected closures; no session engine, MeetingIntelligence bridge or Island
  backend was rewritten.

## Tests run / results (all headless)

- `swift build --package-path Packages/L1-Adapters/ClearlyInput` — **PASS**.
- `swift test --package-path Packages/L1-Adapters/ClearlyInput` after copying
  the four `ClearlyInput*` app test files verbatim into the package test
  target — **PASS, 39 tests, 0 failures**. This covers every PTT and meeting
  table row, Option+E cancellation, tap latch, the 120 s timeout, Ctrl+click,
  debounce, repeat cycles, PTT/meeting independence, all raw-event mapping
  cases, session wiring and the preference migration.
  (The copies were removed afterwards; the tests live only under
  `App/SuperflowApp/Tests/SuperflowAppCoreTests/` as required.)
- `swift build --package-path App/SuperflowApp --target SuperflowAppCore` —
  **BLOCKED** by a compile error in a file outside my ownership:
  `App/SuperflowApp/Sources/SuperflowAppCore/AppEnvironment.swift:66:66:
  default argument cannot be both main actor-isolated and @concurrent`.
  This comes from another agent's concurrent Intelligence-Island work.
  No errors were reported for any of my files in the same compile batch.
- No GUI was opened, no global keystrokes were posted, no windows were
  captured. No git writes were performed.

## Files changed

- `Packages/L1-Adapters/ClearlyInput/**` (new): package manifest plus
  `Gesture.swift`, `RawKeyEventMapper.swift`, `HotkeyService.swift`,
  `PermissionCenter.swift`, `SessionCoordinator.swift`,
  `ClearlyInputController.swift`, and a package-local gesture smoke test.
- `App/SuperflowApp/Package.swift`: added the ClearlyInput package/product to
  the app core and test targets.
- `App/SuperflowApp/Sources/SuperflowAppCore/AppCoordinator+Input.swift`:
  wires the controller, clears the legacy preference, removes the trigger-key
  observer/setting, makes the legacy `.intelligenceDown` event a no-op, and
  stops the tap when Input Monitoring is revoked.
- `Packages/L0-Core/Kernel/Sources/SuperflowKernel/Settings.swift`: added
  `IntelligenceTriggerMigration` (`legacyDefaultsKey` + idempotent `clear`).
- `Packages/L3-Features/FeatureSettings/Sources/SuperflowFeatureSettings/IntelligenceTab.swift`:
  removed the "Trigger key" title, `@AppStorage`, `Segmented` row and updated
  card ranges.
- `App/SuperflowApp/Tests/SuperflowAppCoreTests/ClearlyInputGestureTests.swift`,
  `ClearlyInputMappingTests.swift`, `ClearlyInputSessionTests.swift`,
  `ClearlyInputMigrationTests.swift` (new headless tests).
- This report.

## Unresolved items (for the coordinating agent)

1. The full app build/test cannot be completed until
   `AppEnvironment.swift:66` is fixed by whoever owns that file. My files
   were error-free in the same batch; re-run
   `swift test --package-path App/SuperflowApp --filter ClearlyInput` once it
   compiles.
2. The existing assistant backend answers from the last stored transcript
   (`IslandBridge.prepareAssistant`); there is no live PTT-audio-into-assistant
   capture path in the code. `pttSend` wires to
   `islandBridge.openAssistant(environment:)` and `holdBegan`/`cancelled`, so
   the gesture and Island state are correct without rewriting that backend,
   but composing *new* audio into the answer would need a backend change.
3. The separate dictation-key picker can still be set to right Option or left
   Control, which would overlap the new exclusive bindings. Not changed: it is
   outside my file ownership and was not part of the request.
4. `AppCoordinator+IntelligenceIsland.swift` (another agent) documents Right
   Option opening the typed compose card. That conflicts with push-to-talk;
   the coordinator must decide which surface Right Option owns.
5. `SessionCoordinator.suppressQuestionDetector` defaults to a no-op because
   no existing question-detector hook was available in the owned scope; the
   action is present and tested, and can be wired by the parent.
6. Live tap resilience (watchdog, sleep/wake, Secure Event Input, Option+E in
   another app) cannot be proven headlessly: it needs Input Monitoring and a
   synthetic-CGEvent driver that would touch the user's keyboard. The pure
   mapping and state logic is fully covered; the OS plumbing is implemented
   per the design but not live-verified here.
