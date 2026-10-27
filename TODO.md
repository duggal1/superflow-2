# PLAN.md implementation status

Audit updated: 2026-10-26. This tracks implementation evidence against `PLAN.md` and `DESIGN.md`; source presence alone does not satisfy a phase exit gate.

## Progress

**Estimated source and tooling coverage: 60%. Verified phase exits: 0/9 (automated `make verify` green; device/soak gates remain).** The estimate is a rough equal-weight average across phases 0–8. Runtime, device, soak, distribution, and full acceptance evidence are still missing, so this is not a release-readiness score.

| Phase | Estimate | Status |
|---|---:|---|
| 0. Spikes and decisions | 10% | Six required spikes and owner-device benchmarks are not recorded. ADRs exist but do not replace the spike results. |
| 1. Skeleton | 85% | Package shells, CI, dependency graph, dependency rejection fixture, lint, DesignSystem and Icons exist. Per-port contract coverage and `make verify` are not complete/green. |
| 2. Audio, ASR, journal | 72% | Capture, route-rebuild path, FluidAudio adapter/profile registry, CLI source, segmented Int16 journal, and launch-time crash recovery with a copyable transcript notice exist. Journal, recovery, and ring-buffer tests pass. CLI/ASR build and live ASR acceptance remain unverified. |
| 3. Tier 0 text | 75% | Deterministic stages, package tests and pipeline goldens exist. Full golden/property corpus and all acceptance cases are incomplete. |
| 4. Cleanup and Harper | 35% | llama.cpp, cleanup safety, grammar gate and Rust FFI scaffolding exist. Model benchmarks, built Harper XCFramework, precision goldens and runtime fallback evidence are missing. Harper remains unavailable/disabled unless its binary is built. |
| 5. Input, insertion, session, Island | 55% | Gesture/session/insertion/Island source exists. Real event-tap behavior, focus preservation, target-app matrix, accessibility and long-session memory are unverified. |
| 6. Storage and main window | 78% | SQLite, features, app composition and scheduled retention purge exist. SQLite/TestKit tests pass; migrations from every prior schema, relaunch persistence and full feature acceptance remain unverified. |
| 7. Meetings | 40% | Meeting engine/UI/export scaffolding exists. System audio choice, real dual-stream capture, diarization and 60-minute call acceptance are missing. |
| 8. Hardening and distribution | 38% | LLM inference runs in a packaged XPC helper; the app executable no longer links llama.cpp. `make app` creates a locally ad-hoc-signed bundle. ASR remains in-process; XPC timeouts/crash tests, fault injection, measured budgets, Developer ID signing, notarization and updates remain. |

## Verified in this workspace

### Latest pass (2026-10-26)

- ASR models now download for real: `FluidAudioModelHubDownloader` delegates to FluidAudio's resumable download stack, `FluidAudioRecognizer.prepare` verifies the artifact tree against a SHA-256 sidecar, drops and refetches a corrupt cache, and refuses to load an incomplete one. Onboarding's `downloadModel()` and Settings go through this path; record-time `warmUp` stays offline. 8 new ASR tests (clean-install download, cache reuse, corrupt-cache refetch, incomplete download, failure propagation, offline warm-up, digest stability, invalidation) pass; the ASR package runs 26 tests green.
- Meeting system-lane journal offset: the system lane is journaled on the shared meeting clock, with a real-`FileJournalStore` integration test pinning offset and replay semantics.
- Disk-full is a hard start failure: `SessionEngine.start` rethrows `.diskFull`, finalizes the session as failed and deletes the journal instead of swallowing it.
- Fault injection: `kill -9` mid-session restores every journaled sample and committed row through `RecoveryEngine` against real SQLite; a torn last segment is truncated and its flushed samples survive; journal retention is honored.
- Full-pipeline soak: accelerated and real-time runs of the same audio produce identical transcript row counts, journaled sample counts and text (`SUPERFLOW_SOAK_SECONDS=6 SUPERFLOW_SOAK_REALTIME=1` verified).
- Distribution: `make dmg` produced a 39 MB `dist/Superflow.dmg` and the mounted volume contains `Superflow.app` plus the `/Applications` link; `make app` now embeds `AppIcon.icns` and `Assets.car` and still passes `codesign --verify --deep --strict` and the packaging smoke tests.
- Accessibility: 5 WCAG contrast tests plus the existing design-system suite are green (16 tests); the sidebar uses Hugeicons; the Island already honored Reduce Motion and VoiceOver labels.

- `make lint`: passed after the latest tooling changes (dependency layers, forbidden L0→L1 import fixture, forbidden-pattern lint).
- `make verify`: passed in full on Apple Silicon (build, all package/app/helper/CLI tests, dependency check, forbidden-pattern lint). Harper XCFramework rebuilt via `make harper` and GrammarHarper now links the real backend.
- `swift test --package-path Packages/L1-Adapters/AudioJournal`: passed, 11 tests.
- `swift test --package-path Packages/L1-Adapters/AudioCapture`: passed, 3 tests.
- `swift test --package-path Packages/L1-Adapters/StorageSQLite`: passed, 14 tests.
- `swift test --package-path Packages/L0-Core/TestKit`: passed, 1 test.
- `swift test --package-path Packages/L2-Engines/RecoveryEngine`: passed, 8 tests, including recovered text assembly and cleanup.
- `swift build --package-path App/SuperflowApp --configuration debug`: passed on Apple Silicon.
- `make app`: built and ad-hoc signed `dist/Superflow.app`, including the XPC helper and helper-local `llama.framework`.
- `swift test --package-path App/InferenceHelper --scratch-path App/SuperflowApp/.build`: passed, 5 tests.
- `swift test --package-path Packages/L1-Adapters/LLMLlamaCpp`: passed, 9 tests after splitting the runtime-free cleanup core from the llama-linked runtime.
- `make app-smoke`: passed, including helper/framework embedding and signing checks.
- `codesign --verify --deep --strict dist/Superflow.app`: passed. `otool -L` confirms only the helper links `llama.framework`.
- `SUPERFLOW_SOAK_SECONDS=2 swift test --package-path Tests/Soak`: passed, exact journal sample count, full replay, and RSS measurement verified for the short harness run. The 50 MB limit still requires the planned 1-hour/10-hour soak evidence.
- `tools/gen-fixtures/generate_audio.py` smoke-generated a valid mono PCM16 16 kHz WAV.
- All SwiftPM manifests parse, and `swiftc -frontend -parse` passed for all indexed Swift sources and tests after fixing an invalid escaped-bracket string in a meeting test.
- `python3 -m py_compile` passed for the fixture generator.
- The complete `make verify` target was not run as one uninterrupted command; previously verified package suites were run individually because SwiftPM build caches nearly filled the disk. The app and helper were built successfully with the shared package cache.
- No 1-hour/10-hour soak, real-time soak, device test, or phase exit is claimed as verified.

## Remaining work, ordered by dependency

### Phase 0 — runtime choices

- [ ] Run and record spikes A–F from `PLAN.md`: ASR profile/runtime; S1-mini limits/concurrency; dual ASR/diarization; system audio; Harper FFI/number processing; event taps.
- [ ] Confirm model identifiers, artifacts, checksums, licenses and supported macOS/device constraints from primary sources; update ADRs and verified facts.

### Phase 1 — architecture and verification

- [ ] Add contract tests for every Ports protocol against TestKit fakes and real adapters where hardware permits.
- [ ] Complete Kernel/Ports/TestKit package tests and prove every package builds with `make verify` on a clean Apple Silicon machine.
- [ ] Review dependency rules against the module catalog and keep the generated graph current.

### Phases 2–3 — audio and deterministic text

- [ ] Build and run `superflowctl transcribe` and `superflowctl live`; verify FluidAudio warm and cold starts and cached model readiness.
- [ ] Test audio callback constraints, route changes, permission revocation, ASR watchdog/rotation, kill-and-recover, and one-hour replay on device.
- [ ] Run 1-hour and 10-hour soak targets; compare persisted/replayed samples and transcript rows.
- [ ] Add deterministic-stage golden/property coverage for protected spans, empty input, bounded growth, negative dictionary triggers and shortcut collisions.

### Phases 4–5 — cleanup and interaction

- [ ] Validate llama.cpp/Metal against the pinned S1-mini artifact; measure context, chunk size, worker count, latency and cancellation; add prompt hash verification.
- [ ] Build Harper C ABI/XCFramework; test UTF-16 offsets including emoji/CJK; add grammar goldens and category precision/idempotence/failure evidence.
- [ ] Verify O(1) session memory and end-to-end Fn/Command gestures, insertion/focus, pasteboard restoration and Island interactions.
- [ ] Exercise microphone, Accessibility, Input Monitoring, Globe conflict, secure-field and key-through behavior on macOS.

### Phases 6–8 — product, meetings and release

- [ ] Add migration fixtures for every earlier schema and verify app state and retention behavior across relaunch.
- [ ] Verify every feature and both appearances/accessibility behavior against `DESIGN.md`.
- [ ] Select and validate Core Audio process tap or ScreenCaptureKit; test simultaneous ASR/diarization, echo/gap handling and a 60-minute call/export.
- [x] Add fault-injection coverage (kill -9 recovery over the real journal + SQLite, torn last segment, retention) in `Tests/Integration/FaultInjectionRecoveryTests.swift`.
- [x] Add a full-pipeline soak that compares accelerated and real-time transcript row counts (`Tests/Soak/PipelineRowCountSoakTests.swift`).
- [ ] Add XCUITest E2E and a `Tests/Performance` baseline suite (no Xcode project exists yet; gesture logic stays covered by the pure `GestureRecognizer` tests).
- [ ] Move ASR into XPC; add bounded request deadlines, helper-kill/restart tests.
- [x] Move LLM inference into InferenceHelper XPC, keep llama.cpp out of the app executable, and build the local app bundle with Info.plist, entitlements and ad-hoc signing.
- [x] Add Developer ID signing, notarization, DMG packaging and an update-path decision (`tools/notarize`, `tools/package-dmg`, ADR 0012, `docs/runbooks/distribution.md`). Notarization itself needs the maintainer's certificate and keychain profile and has not been executed here.

## Design and repository gaps

- [x] Design tokens/components and design token map exist.
- [x] App icon set generated from source (`tools/gen-appicon`, `App/Resources/Assets.xcassets`), compiled into `Assets.car`/`AppIcon.icns` by `tools/package-app`, plus an accent color.
- [x] Automated WCAG contrast gate for the color tokens (`DesignSystem/Tests/DesignSystemTests/ContrastTests.swift`); information-bearing `text.3` usages moved to `text.2` per design.md.
- [~] Hugeicons wrapper/resources exist and the app sidebar now uses `HugeIcon` (SF Symbols remain only in menu/context-menu items, where macOS provides them). License confirmation and Exposure Italic bundling/registration remain.
- [ ] Review light/dark appearance, focus, VoiceOver, Reduce Motion/Transparency, contrast, resizing and cursor behavior in the running app.
- [x] Add crash-recovery, model-cache-repair and permissions runbooks.
- [~] Info.plist, entitlements, XPC service metadata and packaging tooling exist; an asset catalog, licensed display font, Developer ID signing and notarization remain.

## Inventory

- 40 package manifests under `Packages/`, one app manifest, one CLI manifest, and three cross-module test manifests (45 total).
- 208 Swift files indexed; 41 test Swift files.
- `Rust/harper-ffi/src/lib.rs` exists but has not been built into a distributable XCFramework.
- `Tests/E2E` and `Tests/Performance` remain empty. App Info.plists, entitlements and InferenceHelper exist; `dist/Superflow.app` is locally built and ad-hoc signed. There is no Xcode project. Fixture instructions and the three operational runbooks now exist.
- `Packages/L0-Core/Kernel/Sources/SuperflowKernel/Models.swift` contains the ASR profile registry. FluidAudio manages the ASR cache; `ModelStore`'s empty `asr` manifest section is not itself an ASR download blocker.
- `RecoveryEngine` runs after model warm-up in the app launch task. It preserves incomplete data when ASR replay fails and exposes recovered transcripts for a menu-bar copy action; the app package now compiles with FluidAudio resolved. Device recovery behavior remains unverified.
- New starts and hotkeys stay gated until the background recovery scan finishes, so a session started during launch cannot be mistaken for a crashed session.
- Multi-speaker diarization remains a known runtime gap: the app composition uses `SingleSpeakerDiarizer`, and the FluidAudio conditional implementation is not linked by the adapter package. The Phase 0 diarization/system-audio spikes remain required before integration.

## Phase 9 — post-v1

- [ ] Defer progressive insertion, correction learning, expanded tech dictionary, Island pause and retention polish until v1 exit gates pass.
