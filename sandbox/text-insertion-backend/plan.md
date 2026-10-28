# Plan: harden the Superflow text-insertion backend

## Objective

Replace the current minimal `SystemTextInserter` with the full paste backend described in the
supplied `TextInsertion.swift` (focus detection, trusted-Accessibility check, frontmost/target
verification, layout-correct Cmd+V, clipboard snapshot/transient write/guarded restore, paste
verification, Accessibility fallback, and a detailed report), while making it compile under
Swift 6 strict concurrency and fit Superflow's existing L0/L1 package boundaries.

The supplied file is **behavioural reference only**; it is vendored at
`sandbox/text-insertion-backend/reference/TextInsertion.swift` so an implementer can compare
against it. It does not compile as-is and must not be dropped into the package. **The
"Behaviour contract" section below is normative** where the reference and this plan differ.
Its known defects are listed below.

## End state / definition of done

1. `Packages/L1-Adapters/TextInsertion` builds and tests cleanly on Swift 6.4 / macOS 15+.
2. `SystemTextInserter` keeps its `TextInserter` contract and gains:
   * record-start preparation (`prepareForInsertion()`) so Chromium/Electron apps expose AX;
   * a detailed `TextInsertionReport` available to tests and to the app;
   * a never-lose-text failure path: every non-secure failure leaves the transcript on the
     clipboard and maps to `.clipboardOnly`, which the existing Island bridge turns into its
     "Couldn't paste. Transcript ready to copy." card;
   * secure-field detection that never inserts and never overwrites the clipboard.
3. The Island's failure card is rebuilt from the **finalized repository record**, not the last
   partial. This is a small existing-bridge correction, not new UI.
4. `HotkeyEngine` ignores every event carrying the synthetic-paste marker in both its passive
   and active taps.
5. `SessionEngine.start()` calls `prepareForInsertion()` before model warm-up; `SessionEngine.stop()`
   still calls `insert(_:strategy: .auto)`, with a deadline large enough for the documented
   worst case and a `.clipboardOnly` fallback if that deadline is hit.
6. Clipboard restore happens only after a successful insertion (paste **or** AX fallback), after
   500 ms by default, and only if `changeCount` proves no other process wrote.
7. No transcript text is logged; only enum/step tags are.
8. `swift test --package-path Packages/L1-Adapters/TextInsertion`,
   `.../HotkeyEngine`, `.../SessionEngine`, `swift build --package-path App/SuperflowApp`,
   and `make lint` pass.
9. A fresh manual pass lands text in TextEdit, Notes, Slack, Chrome, VS Code, Terminal, and a
   password field (blocked, copy card shown).

## Non-goals

* Fn double-tap / right-Command gesture changes (the gesture code already exists; this plan only
  filters synthetic events).
* Escape-undo window.
* Filler/duplicate cleanup, GPU/model work, or prompt files.
* New Island UI. The failure/copy card already exists; this plan only corrects which transcript
  feeds it.
* Rewriting the Accessibility permission flow or TCC prompts.
* App Store distribution or sandboxing.
* Changing the `InsertionOutcome` cases beyond the additive prepare method.

## Environment and ground truth (verified)

| Fact | Value |
|---|---|
| Repo | `/Users/harshitduggal/workspace/superflow` |
| Language | Swift 6, strict concurrency, `swiftLanguageModes: [.v6]` |
| Toolchain | Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27.1, macOS 27.2 SDK |
| Deployment target | macOS 15 |
| Existing insertion package | `Packages/L1-Adapters/TextInsertion` (`SystemTextInserter.swift`, 217 lines) |
| Existing port | `SuperflowPorts.TextInserter` + `InsertionStrategy` + `InsertionOutcome` in `Packages/L0-Core/Ports/Sources/SuperflowPorts/Text.swift` |
| Existing contract test | `TextInserterContract` in `Packages/L0-Core/TestKit/Sources/SuperflowTestKit/TextContracts.swift` |
| Existing insertion tests | 9 tests in `Packages/L1-Adapters/TextInsertion/Tests/TextInsertionTests/TextInsertionTests.swift` |
| Hotkey | `Packages/L1-Adapters/HotkeyEngine`; passive tap masks `flagsChanged` + `keyDown`, active tap masks `keyDown` |
| Session | `SessionEngine.start()` records `frontmostBundleID`; `stop()` calls `inserter.insert(text, strategy: .auto)` inside `withDeadline(.milliseconds(insertionMs))`, currently 3_000 ms |
| Island | `IslandBridge` maps `.clipboardOnly` / `.blockedSecureField` to `pasteFailed`, but currently calls `fail(id: nil)`, which uses the last `.partial` rather than the finalized record |
| Test commands | `swift test --package-path <pkg>`, `make verify`, `make lint` |
| Logging convention | `Logger(subsystem: "com.superflow.app", category: "text-insertion")` |
| Hard lint limits | 400 lines per Swift source file, no `print()` in packages/app |

The current TextInsertion package builds today (`swift build` verified), so the new work must
not regress it.

## Components

| id | component | responsibility |
|---|---|---|
| c1 | Cross-layer contracts | Marker constant in L0 Kernel; additive `prepareForInsertion()` on the L0 port; no duplicate public type names |
| c2 | Focus inspection | `@MainActor` AX target wrapper, role classification, secure-field detection, Chromium detection, `prepare()` |
| c3 | Paste engine | Clipboard snapshot/transient write/guarded restore, layout key resolution, private-source Cmd+V, modifier wait, verification, AX fallback |
| c4 | Report and adapter | `TextInsertionReport` + mapping to the existing `InsertionOutcome`; strategy semantics |
| c5 | Session/Island integration | Prepare at record start, insert at submit with a safe deadline, and feed the failure card the finalized transcript |
| c6 | Hotkey isolation | Both taps ignore events whose `eventSourceUserData` equals the marker |
| c7 | Verification and docs | Unit/service/cross-package/manual tests, ADR, permissions runbook, PLAN.md |

## Target file layout

All new source files stay below 400 lines.

```
Packages/L0-Core/Kernel/Sources/SuperflowKernel/
  SyntheticInput.swift                 # marker value only (no CoreGraphics import)

Packages/L0-Core/Ports/Sources/SuperflowPorts/
  Text.swift                           # + prepareForInsertion() requirement + default no-op

Packages/L0-Core/TestKit/Sources/SuperflowTestKit/
  FakeText.swift                       # RecordingInserter prepare counter + ordered events
  FakeRecognition.swift                # optional onWarmUp hook for ordering test

Packages/L1-Adapters/TextInsertion/Sources/SuperflowTextInsertion/
  InsertionTypes.swift                 # focus/method/failure/result, options, report
  LayoutPasteKeyResolver.swift         # UCKeyTranslate, main-thread only
  AXTextTarget.swift                   # @MainActor wrapper around one AXUIElement
  AXValueReplacement.swift            # pure value+range replacement helper (AX fallback)
  AXRoleClassifier.swift               # pure role/subrole/settable -> InsertionFocus
  AXFocusInspector.swift               # focused-element lookup + Chromium detection + prepare
  PasteboardSnapshot.swift             # full item/type snapshot + completeness flag
  SystemPasteboard.swift               # PasteboardAccess implementation over NSPasteboard
  PasteEventPoster.swift               # private CGEventSource, explicit Cmd flags, marker
  InsertionRestore.swift               # RestoreScheduling seam + secure-input probe
  InsertionReportBuilder.swift         # step-tag vocabulary, duration, report assembly
  TextInsertionService.swift           # actor decision tree + report
  SystemTextInserter.swift             # TextInserter adapter, strategy mapping, prepare hook

T5 note: the old PasteboardType extensions move to SystemPasteboard.swift so the old tests
and the pre-T8 inserter stay green; they are not deleted until T8's test rewrite.

Packages/L1-Adapters/TextInsertion/Tests/TextInsertionTests/
  InsertionTypesTests.swift
  AXRoleClassifierTests.swift
  AXValueReplacementTests.swift
  PasteboardSnapshotTests.swift
  PasteEventPosterTests.swift
  InsertionRestoreTests.swift
  TextInsertionServiceTests.swift
  SystemTextInserterTests.swift        # replaces/updates current TextInsertionTests.swift

Packages/L1-Adapters/HotkeyEngine/Sources/SuperflowHotkeyEngine/
  KeyEventMapper.swift                 # + isSynthetic(_ event:)
  HotkeyEngine.swift                   # early return in both tap callbacks

Packages/L1-Adapters/HotkeyEngine/Tests/HotkeyEngineTests/
  KeyEventMapperTests.swift            # + marker test

Packages/L2-Engines/SessionEngine/Sources/SuperflowSessionEngine/
  SessionEngine.swift                  # prepare call + 8 s insertion deadline + clipboard fallback

Packages/L2-Engines/SessionEngine/Tests/SessionEngineTests/
  SessionTests.swift                   # prepare/order/deadline assertions

App/SuperflowApp/Sources/SuperflowAppCore/
  IslandBridge.swift                   # failure card uses the finalized record

App/SuperflowApp/Tests/SuperflowAppCoreTests/
  IslandBridgeTests.swift              # finalized text, not last partial

App/SuperflowApp/Package.swift         # test target gains TestKit (test-only)

docs/adr/0021-text-insertion-backend.md
docs/runbooks/permissions.md
PLAN.md                                # section 15: 500 ms, verification, secure-field policy
sandbox/text-insertion-backend/reference/TextInsertion.swift
```

## Public API decisions (pin these before coding)

### Kernel marker (no CoreGraphics dependency)

```swift
public enum SyntheticInputMarker {
    /// ASCII "SFPASTE1"; written to CGEventField.eventSourceUserData.
    public static let value: Int64 = 0x5346_5041_5354_4531
}
```

Both L1 adapters compare against this constant. `TextInsertion` also exposes
`SyntheticInput.isSynthetic(_ event: CGEvent) -> Bool` for its tests; the hotkey side adds
`KeyEventMapper.isSynthetic(_ event: CGEvent) -> Bool`.

### Port addition (source-compatible)

```swift
public protocol TextInserter: Sendable {
    func insert(_ text: String, strategy: InsertionStrategy) async throws -> InsertionOutcome
    func frontmostBundleID() async -> String?
    /// Called when recording starts, before warm-up. Default: no-op.
    func prepareForInsertion() async
}

public extension TextInserter {
    func prepareForInsertion() async {}
}
```

This keeps every existing conformer compiling; only `SystemTextInserter` overrides it.

### TextInsertion types (rename to avoid the Ports collision)

* `InsertionFocus` (`editable(role:)`, `notEditable(reason:)`, `secure`, `unknown(reason:)`)
* `InsertionMethod` (`paste`, `accessibility`)
* `InsertionFailure` (`emptyText`, `accessibilityNotTrusted`, `secureField`,
  `noEditableTarget`, `targetNotFrontmost`, `eventPostFailed`, `pasteNotObserved`)
* `TextInsertionResult` (`inserted(method:verified:)`,
  `notInserted(InsertionFailure, textOnClipboard: Bool)`)
* `TextInsertionOptions`:
  * `targetPID: pid_t?`
  * `restoreClipboard = true`
  * `clipboardRestoreDelay = .milliseconds(500)`
  * `verifyTimeout = .milliseconds(400)`
  * `modifierReleaseTimeout = .milliseconds(300)`
  * `allowPaste = true`
  * `preferAccessibility = false`
  * `allowAccessibilityFallback = true`
  * `writeClipboardOnFailure = true`
  * `postTap = .cghidEventTap`
* `TextInsertionReport` (`result`, `focus`, `axTrusted`, `keyCode`, `steps`, `durationMs`,
  `clipboardRestoreScheduled`)

`InsertionOutcome` is **not** redefined in this package.

### Injectable seams (for tests)

```swift
@MainActor public protocol InsertionTarget: AnyObject, Sendable {
    func characterCount() -> Int?
    func selectionLength() -> Int?
    func insertSelectedText(_ text: String) -> Bool
}

@MainActor public protocol FocusInspecting: AnyObject, Sendable {
    func inspect(pid: pid_t) -> (focus: InsertionFocus, target: (any InsertionTarget)?)
    func prepare(pid: pid_t)
}

public protocol PasteboardAccess: Sendable {
    func changeCount() async -> Int
    func writeTransient(_ text: String) async -> Int?
    func snapshot(maxBytes: Int) async -> PasteboardSnapshot?
    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount expected: Int) async
}

public protocol PasteEventPosting: Sendable {
    var isTrusted: Bool { get }
    func postPaste(keyCode: CGKeyCode) async -> Bool
}

@MainActor public protocol PasteKeyResolving: Sendable {
    func pasteKeyCode() -> CGKeyCode
}

public protocol FrontmostAppProviding: Sendable {
    func frontmostPID() async -> pid_t?
    func selfPID() async -> pid_t
    func activate(pid: pid_t) async
}

public protocol RestoreScheduling: Sendable {
    @discardableResult
    func schedule(after delay: Duration,
                  _ action: @escaping @Sendable () async -> Void) -> Task<Void, Never>
}
```

`AXTextTarget` is a `@MainActor final class` (implicitly `Sendable`) holding the non-Sendable
`AXUIElement`; this is the only place an AX element is stored across an `await`.

### Production wiring (Swift 6 isolation)

```swift
public actor TextInsertionService {
    @MainActor
    public static func live(pasteboard: NSPasteboard = .general) -> TextInsertionService

    public init(focus: any FocusInspecting,
                clipboard: any PasteboardAccess,
                poster: any PasteEventPosting,
                keyResolver: any PasteKeyResolving,
                apps: any FrontmostAppProviding,
                restoreScheduler: any RestoreScheduling,
                secureInput: @escaping @Sendable () -> Bool = { IsSecureEventInputEnabled() },
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                preparedTargetTTL: Duration = .seconds(600))
}

public final class SystemTextInserter: TextInserter, @unchecked Sendable {
    @MainActor
    public convenience init(pasteboard: NSPasteboard = .general) {
        self.init(service: TextInsertionService.live(pasteboard: pasteboard))
    }
    public init(service: TextInsertionService)
}
```

`AppEnvironment` is already `@MainActor`, so `SystemTextInserter()` keeps compiling there.
Tests construct `SystemTextInserter(service:)` off the main actor with fakes.

## Behaviour contract (normative)

### Target selection and prepared-PID lifetime

* `prepareForInsertion()` captures `NSWorkspace.shared.frontmostApplication?.processIdentifier`
  and calls `service.prepare(targetPID:)`.
* `prepare(targetPID:)` stores `(pid, ContinuousClock.now)`; `preparedTargetTTL` defaults to
  600 s. The prepared target is **consumed (cleared) after the first insert resolution**, so a
  later History copy or a new session can never activate an old app.
* At submit, resolve the target as:
  1. current frontmost PID;
  2. if current is Superflow itself, use the prepared PID and activate it;
  3. if current is nil, use the prepared PID;
  4. ignore the prepared PID if it is older than `preparedTargetTTL`.
* If the resolved target is not frontmost after activation, fail with
  `.targetNotFrontmost`; write transient text and return `.clipboardOnly`.
* This avoids yanking the user back to an old app if they deliberately switched, while still
  recovering when the Island stole focus.

### Focus rules

* `AXSecureTextField` (role or subrole) -> `.secure`; never insert, never write the clipboard,
  return `.blockedSecureField`.
* Editable roles (`AXTextField`, `AXTextArea`, `AXComboBox`, `AXSearchField`), settable
  `AXValue`, or an `AXEditableAncestor` -> `.editable`.
* Unambiguous non-editable controls (`AXButton`, `AXStaticText`, `AXMenuItem`, `AXMenu`,
  `AXToolbar`, `AXRadioButton`, `AXCheckBox`, `AXPopUpButton`, `AXSlider`, `AXDockItem`,
  `AXImage`, `AXList`, `AXOutline`, `AXTable`, `AXRow`, `AXCell`, `AXColumn`) ->
  `.notEditable`.
* Everything else — including `AXWindow`, `AXGroup`, `AXScrollArea`, `AXWebArea`, and a
  missing focused element — -> `.unknown`; **attempt the paste**, because Electron/Chrome and
  some native apps hide the real field behind an unclassified container.
* `prepare(pid:)` sets `AXManualAccessibility = true` on the app, with a 0.3 s messaging
  timeout. Do **not** set `AXEnhancedUserInterface` (it breaks window animations/tiling).

### Paste pipeline

1. Reject empty text with `.emptyText` (adapter maps to `.pasted`, preserving the contract).
2. Check `AXIsProcessTrusted()`. If false: write transient text if possible, return
   `.accessibilityNotTrusted` with `textOnClipboard` reflecting the write.
3. Snapshot the clipboard **before** writing; if any type cannot be read or the snapshot
   exceeds 64 MB, mark it incomplete and never restore.
4. Write one `NSPasteboardItem` with `.string` plus empty marker data for
   `org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType`, and
   `org.nspasteboard.AutoGeneratedType`. Return `changeCount` after the write.
5. If `IsSecureEventInputEnabled()` is true, skip the synthetic paste (Terminal/password
   prompts swallow it), append `secure-input`, and go straight to the AX fallback.
6. Wait up to 300 ms for Command/Option/Control/Shift/Fn flags to clear.
7. Resolve the key code on `@MainActor` with `UCKeyTranslate` using the Command modifier state,
   scanning 0..<128 for `v`/`V`; fallback `kVK_ANSI_V` (9).
8. Post key-down, sleep 8 ms, post key-up from a `.privateState` `CGEventSource`, with
   `flags = .maskCommand` and `eventSourceUserData = SyntheticInputMarker.value`, to
   `.cghidEventTap` by default.
9. Verify only when a character-count baseline is safe (focused target has a count and a zero
   selection): poll every 40 ms up to 400 ms for a changed count.
10. If paste was posted but not observed, try AX selected-text insertion; if AX succeeds, mark
    `.inserted(method: .accessibility, verified:)`.
11. If nothing landed: return `.notInserted(.eventPostFailed` or `.pasteNotObserved,
    textOnClipboard: true)`. Never restore the clipboard after a failure.
12. If something landed and the snapshot is complete: schedule a restore after 500 ms through
    the injected `RestoreScheduling`, and restore **only if** `changeCount == ourChangeCount`.
    Restore after both `.paste` and `.accessibility` successes, because the text already landed.

Strategy order in the service is controlled by options:

| Options | Service order |
|---|---|
| defaults (`.auto`) | paste -> AX fallback -> failure |
| `allowAccessibilityFallback = false` (`.pasteboard`) | paste -> failure |
| `preferAccessibility = true`, `allowPaste = false` (`.accessibility`) | AX -> failure |
| `.clipboardOnly` | adapter writes transient text directly; no service paste |

### Adapter mapping (`SystemTextInserter.insert(_:strategy:)`)

| Strategy | Behaviour |
|---|---|
| `.clipboardOnly` | check focus first: `.secure` -> `.blockedSecureField`; else write transient and return `.clipboardOnly("Copied to the clipboard.")` |
| `.accessibility` | try AX first; on failure write transient and return `.clipboardOnly` |
| `.pasteboard` | paste only; on failure write transient and return `.clipboardOnly` |
| `.auto` | paste -> AX fallback -> clipboard |

Report mapping:

| `TextInsertionResult` | `InsertionOutcome` |
|---|---|
| `.inserted(.paste, _)` | `.pasted` |
| `.inserted(.accessibility, _)` | `.accessibility` |
| `.notInserted(.secureField, _)` | `.blockedSecureField` |
| `.notInserted(.emptyText, _)` | `.pasted` |
| any other `.notInserted` | `.clipboardOnly(reason:)` |

Every `.clipboardOnly` must be truthful: the service writes transient text on
`.noEditableTarget`, `.targetNotFrontmost`, `.eventPostFailed`, and `.pasteNotObserved`;
secure and empty are the only no-write cases. The adapter must not throw for expected insertion
failures.

### Step vocabulary (never transcript text)

`empty`, `ax-untrusted`, `no-target`, `focus-editable`, `focus-not-editable`, `focus-secure`,
`focus-unknown`, `pb-write-failed`, `pb-written`, `secure-input`, `cmdv-posted`,
`cmdv-failed`, `verified`, `paste-not-observed`, `unverifiable`, `ax-verified`,
`ax-not-observed`, `ax-set-failed`, `not-frontmost`.

### Session deadline

`SessionEngine` must cover the worst case (300 ms modifier wait + AX activation/reads + 400 ms
verify + AX fallback + 400 ms re-verify). Raise `insertionMs` to 8_000 and make it an init
parameter (`insertionDeadline: Duration = .seconds(8)`). In the `catch`, make a best-effort
`try? await inserter.insert(text, strategy: .clipboardOnly)` before emitting the notice, so
the "text is on the clipboard" message is true.

### Island failure payload

In `IslandBridge.handle(.inserted)`, do not call `fail(id: nil)` for `.clipboardOnly` /
`.blockedSecureField`. Set `didLand = false` and let the existing
`.finished(id, .complete)` branch call `fail(id: id)`, which rebuilds the card from the
finalized repository record. No new UI.

## Known defects in the supplied file and the fix

| # | Defect | Fix |
|---|---|---|
| 1 | `InsertionOutcome` redeclared, colliding with `SuperflowPorts.InsertionOutcome` | Rename the local result to `TextInsertionResult`; map in the adapter |
| 2 | `AXUIElement` stored in a `Sendable` report/inspection and passed across actor boundaries | `@MainActor AXTextTarget` class; reports carry only Sendable enums/strings |
| 3 | `unsafeBitCast(raw, to: CFData.self)` on the TIS pointer | `Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()` |
| 4 | `unsafeBitCast(v, to: AXUIElement.self)` on CF values | `guard CFGetTypeID(v) == AXUIElementGetTypeID(); let el = v as! AXUIElement` |
| 5 | `kUCKeyTranslateNoDeadKeysMask` passed as integer `1` | Use `OptionBits(kUCKeyTranslateNoDeadKeysBit)` and the existing `kUCKeyActionDisplay` pattern |
| 6 | `kAXNumberOfCharactersAttribute` assumed present | Use it when available; otherwise fall back to `(kAXValueAttribute as? String)?.utf16.count`; if neither exists, baseline is nil (unverifiable) |
| 7 | Restore only when `method == .paste` | Restore after any success (`paste` or `accessibility`) when snapshot is complete |
| 8 | Secure field writes the transcript to the clipboard | Do not write; return `.blockedSecureField`; Island card offers Copy |
| 9 | One 700-line file | Split by responsibility per the layout above |
| 10 | `SystemTextInserter` could create a fresh service per call, losing `preparedPIDs` | One `TextInsertionService` instance owned by `SystemTextInserter` |
| 11 | `CGEventTapLocation`/`NSPasteboard` Sendable warnings | Verify `TextInsertionOptions` compiles; otherwise store the tap as a raw `UInt32`. `SystemPasteboard` is `@unchecked Sendable` and serialises access |
| 12 | `AXIsProcessTrusted()` false is silent | Report `axTrusted` + `steps == ["ax-untrusted"]`; write transient text for the copy card |
| 13 | Detached restore is not awaitable in tests | Inject `RestoreScheduling`; production uses `Task.detached`, tests use an inline/awaitable scheduler |
| 14 | No secure-input detection | Check `IsSecureEventInputEnabled()` and fall back to AX with a `secure-input` step |

## Tasks

| id | title | components | depends on | est. LOC |
|---|---|---|---|---|
| T1 | Kernel synthetic-event marker | c1, c6 | — | 60 |
| T2 | Add `prepareForInsertion()` to the port | c1, c5 | — | 70 |
| T3 | Insertion types, options, report, layout key resolver | c2, c3 | — | 240 |
| T4a | AX target, value replacement, role classifier | c2 | T3 | 220 |
| T4b | AX focus inspector, Chromium detection, prepare | c2 | T4a | 220 |
| T5 | Clipboard snapshot and transient pasteboard | c3 | T3 | 220 |
| T6 | Private-source synthetic paste poster | c3, c6 | T1, T3 | 160 |
| T7a | Restore scheduler, secure-input probe, report builder | c4 | T3 | 160 |
| T7b | `TextInsertionService` decision tree | c3, c4 | T4b, T5, T6, T7a | 280 |
| T8 | `SystemTextInserter` adapter and outcome mapping | c4, c5 | T2, T7b | 240 |
| T8b | Island failure card uses the finalized transcript | c5 | T8 | 120 |
| T9 | Hotkey taps ignore synthetic events | c6 | T1 | 80 |
| T10 | Prepare + safe deadline at record start/submit | c5 | T2 | 100 |
| T11 | ADR, runbook, full verification | c7 | T8b, T9, T10 | 120 |

Execution order:
**T1 -> T2 -> T3 -> T4a -> T4b -> T5 -> T6 -> T7a -> T7b -> T8 -> T8b -> T9 -> T10 -> T11**.
`tasks.json` is the executable source of truth (signatures, paths, subtests, acceptance).

## Test strategy

* **Pure/unit:** role classifier, value+range replacement, key resolver fallback, transient
  write markers, snapshot completeness, restore change-count guard, event flags/marker,
  adapter mapping, step vocabulary.
* **Service with fakes:** trusted/untrusted, secure, not-editable, no target, frontmost stolen,
  stale prepared PID, secure input, paste verified, paste unverified, paste failed + AX
  success, paste + AX both fail, restore after AX success, restore skipped after failure,
  restore skipped if a new copy races, strategy options.
* **Cross-package:** `SessionEngine.start()` calls `prepareForInsertion()` before `insert`;
  insertion deadline fallback; `HotkeyEngine` marker helper.
* **Island:** `.clipboardOnly` then `.finished(.complete)` produces `pasteFailed` whose text is
  the finalized repository transcript, not the last partial.
* **Manual:** TextEdit, Notes, Slack, Chrome, VS Code, Terminal, password field, Finder desktop.
  Inspect `report.steps` on failure; never log transcript text.
* **Permission regression:** with a stale/ad-hoc signature, `AXIsProcessTrusted()` is false even
  though Settings shows the toggle ON. Document `tccutil reset Accessibility <bundle.id>` and
  a stable Development/Developer ID signature.

## Risks and open questions

* **Risk — TCC identity:** unsigned/ad-hoc rebuilds change the code identity and invalidate
  Accessibility. The code reports it; the fix is signing, not code.
* **Risk — AX latency:** Electron/Chrome can take 300 ms+ to build the AX tree. `prepare()` at
  record start plus a 0.3 s messaging timeout is the mitigation; `unknown` still attempts paste.
* **Risk — TIS on a background thread** crashes on current macOS. The resolver is
  `@MainActor`; do not move it.
* **Risk — clipboard managers:** the three `org.nspasteboard` markers are required; empty
  data is the convention, not `Data([0x31])`.
* **Risk — Secure Input:** Terminal and password prompts swallow synthetic Cmd+V even with
  Accessibility; detect it and use AX or the copy card instead of silently failing.
* **Risk — multi-app switch:** plan chooses the current frontmost app at submit, except when
  Superflow itself is frontmost. If product wants "always the app from record start", that is a
  one-line change in `TextInsertionService`, but it can steal focus.
* **Open question:** for a secure field, should the transcript be auto-copied (concealed) or
  only offered through the Island Copy button? This plan chooses the Island button only.
* **Open question:** should `.accessibility` fallback restore the clipboard immediately rather
  than after 500 ms? Plan uses the same 500 ms guard for both paths.
* **Out of scope:** the GPU/Nemotron note in the request is unrelated to insertion; do not
  change model compute units here.

## How to execute

1. Work task-by-task in `order`; keep the package green after every task.
2. For each task run its package test command before moving on.
3. After T8, run the full TextInsertion suite and `swift build --package-path App/SuperflowApp`.
4. After T10, run `swift test --package-path Packages/L2-Engines/SessionEngine` and
   `swift test --package-path Packages/L1-Adapters/HotkeyEngine`.
5. Finish with `make lint` and the manual permission matrix; record results in the task/PR.
