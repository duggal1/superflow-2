# Fix these issues from the full test sweep

Testing-only pass on 2026-10-25. No source code was modified. Run all affected tests again after fixes.

## Confirmed source and test failures

1. **Diagnostics compile failure** — `Packages/L1-Adapters/Diagnostics/Sources/SuperflowDiagnostics/Diagnostics.swift:97` calls `signposter.endInterval(name, id: id)`, but this SDK requires the interval state from `beginInterval`. Retain/pass that state, and address the unused return warning at line 93.

2. **HotkeyEngine compile failure** — `Packages/L1-Adapters/HotkeyEngine/Sources/SuperflowHotkeyEngine/HotkeyEngine.swift:171,198` passes `CGEventTapProxy` to `CGEvent.tapEnable`, which requires `CFMachPort`. Keep and use the actual tap port; do not cast the proxy.

3. **PermissionsKit Swift 6 Sendable failure** — `Packages/L1-Adapters/PermissionsKit/Sources/SuperflowPermissionsKit/GlobeKeyProbe.swift:9` stores non-Sendable `UserDefaults` in a Sendable-conforming struct. Establish a safe isolation boundary; do not silence this with an unchecked conformance without proving safety.

4. **SystemAudioCapture compile failure** — `Packages/L1-Adapters/SystemAudioCapture/Sources/SuperflowSystemAudioCapture/SystemAudioCapture.swift:101`: `SCStream.removeStreamOutput` throws in this SDK. Handle the error during shutdown cleanup.

5. **TextInsertion test failure** — `Packages/L1-Adapters/TextInsertion/Tests/TextInsertionTests/TextInsertionTests.swift:97`, `testAutoFallsBackToClipboardWhenBothFail`: expected clipboard text `"keep me"`, received `nil`. Verify the clipboard restoration contract and fix production behavior or the test based on that contract.

6. **LLMLlamaCpp Swift 6 isolation failure** — `Packages/L1-Adapters/LLMLlamaCpp/Sources/SuperflowLLMLlamaCpp/LlamaCppRuntime.swift:15-16`: nonisolated `deinit` accesses non-Sendable `OpaquePointer?` fields `context` and `model`. Provide a safe ownership/deallocation design compatible with Swift 6.

7. **Harper adapter cannot build** — `Packages/L1-Adapters/GrammarHarper` references local binary target `Rust/harper-ffi/HarperFFI.xcframework`, which does not contain a binary artifact. Build/package the framework through the repository's documented Harper flow, or make the dependency arrangement valid for tests.

8. **Icons compile failure, blocks dependent UI/features** — `Packages/L4-UI/Icons/Sources/SuperflowIcons/HugeIcon.swift:129` references `Tok.text` with no `Tok` in scope. Resolve the API/dependency boundary without creating a cycle. This blocks Icons, UIComponents, and all attempted L3 feature package builds.

9. **DesignSystem test failure** — `Packages/L4-UI/DesignSystem/Tests/DesignSystemTests/DesignSystemTests.swift:35-36`, `testBadgeCycleWrapsBothWays`: negative indices yield `.rose` and `.blue` where the test expects `.blue` and `.green`. Normalize negative modulo indices in `BadgeVariant.at` or correct the intended contract/test.

10. **ASR package reports dependency/credential failure** — all 5 `ASRFluidAudio` XCTest cases passed, but `swift test` exited 1 with `Failed to find credentials for 'https://github.com' in keychain: status -128` during resolution/artifact handling. Fix or document dependency acquisition so the package command exits successfully without relying on unavailable keychain credentials.

## Suite results

- 38 standard package test targets with Swift test sources were attempted. 19 package commands completed successfully. ASRFluidAudio ran 5 passing tests but its package command exited unsuccessfully as noted above.
- Engine and core behavior suites that completed: TestKit, AudioCapture, AudioJournal, DiarizationFluidAudio, ModelStore, StorageSQLite, GestureKit, MeetingEngine, RecoveryEngine, SessionEngine, StatsEngine, TextCleanup, TextCommands, TextGrammarGate, TextLexicon, TextLineFormat, TextNumbers, TextPipeline, TextShortcuts.
- Package commands blocked by confirmed failures: Diagnostics, GrammarHarper, HotkeyEngine, LLMLlamaCpp, PermissionsKit, SystemAudioCapture, TextInsertion, all eight attempted feature packages, DesignSystem, Icons, and UIComponents.
- `make test-fast` was rerun and exits at Kernel with `error: no tests found`; Kernel declares an empty test target. Ports also declares an empty target. `Tests/Golden` and `Tests/Integration` store test sources under `Sources`, outside the default `Tests/` lookup. Golden passed (1 test, 0 failures). Integration was attempted, but package resolution stopped because the local HarperFFI binary framework is missing.
- `make lint-forbidden` also fails after FluidAudio resolution: all 96 reported long-source violations are in `.build/checkouts/FluidAudio` (confirmed by filtering those paths). The linter scans dependency checkouts beneath `Packages`; exclude generated `.build` content from its scan. No non-dependency lint violations were reported. The one-hour accelerated soak wrote and replayed the full sample count. First run exceeded the 50 MiB RSS-growth limit (63,373,312 bytes); a repeat passed in 48.764 seconds. Treat this as a potentially noisy memory gate until repeated measurements confirm stability. The 10-hour accelerated journal soak passed (199.933 seconds, full sample count and replay). The 10-hour real-time soak and the plan’s accelerated-versus-real-time transcript row-count comparison remain unrun.

## Retest

After fixing these items, run each affected package suite, then the full fast suite, Golden/Integration coverage, the 10-hour real-time soak, model/runtime tests with required artifacts, and `make verify`. At the start of this pass the volume had 9.3 GiB free; it had about 6.5 GiB after the package sweep.
