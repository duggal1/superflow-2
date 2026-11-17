# Validation report — Dynamic Island intelligence rebuild

Refreshed after the final integration and the coordinator's repairs.
Generated: 2026-11-17 (final verification pass).

## Command evidence (real runs, this working tree)

Release build:
- `swift build --package-path App/SuperflowApp --configuration release` →
  `rc=0`, `Build complete!`

Focused suites (all green):
- `swift test --package-path Packages/L3-Features/FeatureIsland` → 106 tests, 0 failures
- `swift test --package-path Packages/L1-Adapters/ClearlyInput` → 4 tests, 0 failures
- `swift test --package-path Packages/L1-Adapters/ClearlyStealth` → 25 tests, 0 failures
- `swift test --package-path Packages/L3-Features/FeatureIntelligence` → 14 tests, 0 failures
- `swift test --package-path Packages/L3-Features/FeatureSettings` → 34 tests, 0 failures
- `swift test --package-path App/SuperflowApp` → 97 tests, 0 failures

Lint:
- `tools/lint-forbidden` → `rc=0`, `Forbidden-pattern lint passed.`

Harness:
- `VH_TIMEOUT=600 tools/validate-headless/validate-headless --no-fail` →
  PASS 19 / FAIL 0 / UNVERIFIED 2 (R2 process claim; R21 PR pending at run time).

## Repairs made in this final pass (root causes, not test weakening)

1. `IntelligenceContentPanels.swift` — repaired broken `VStack` braces left by an
   interrupted agent edit (build was red) so the Permissions/About groups sit
   inside the settings panel.
2. Lint (4 categories) — rebuilt Island views now compose the shared
   `IconView` / `IconButton` / `RowButton` / `AppButton` / `AppField` components
   instead of raw `Button` / `Image(systemName:)` / `.font(.system(size:))`;
   the stealth driver uses `FileHandle.standardOutput.write` instead of `print`.
   Added the real SF Symbol glyph `Icon.circle`.
3. `IslandBridgeTests.testCompletionWithoutInsertionRetracts` — moved the
   honest-stealth-status notice out of `IslandBridge.start()` (a low-level event
   pump) into `AppCoordinator.finishLaunch()`, its proper app-launch layer. The
   required R17 status behaviour is unchanged; the bridge no longer injects an
   unrelated notice into a one-off test session.
4. `WarmupGestureTests` — the test asserted the superseded legacy trigger-key
   behaviour (`.intelligenceDown` opening the assistant). R7/R8 deliberately
   made that event inert because Right Option is handled only by ClearlyInput's
   listen-only tap (otherwise one press opens the surface twice). Updated the
   test to assert the new design AND to positively verify the real
   `openIntelligenceCompose()` path still opens the assistant. All original
   meaningful invariants (no dictation gesture, idle gesture state, selection,
   distinct icons) are retained — coverage was strengthened, not removed.
5. `SettingsValidation.cleanupWorkersRange` — was `1...8` while the shipped
   default (commit c6a568d) is 10, so `isValid` was false out of the box and 16
   `SettingsViewModelTests` failed. Corrected to `1...10`, matching the default
   while still rejecting 12 (as its frozen test requires).
6. Harness false negatives — `check-15`/`check-16` quoted a two-path `$src` as a
   single grep argument (0 hits despite features present); `integrity-tests.sh`
   used a stale gutter-assertion literal. Both corrected.

## Frozen-test integrity

`IdleLampMotionTests.swift` and `IslandSnapshotTests.swift` are byte-identical
to git HEAD (shasums match); `testLongCancelledTranscriptKeepsUndoInsideTheContentGutter`
and both assertions are present. No frozen test was deleted or weakened.

## Completion audit — two consecutive clean passes

AUDIT_PASSES=2

- Pass 1: release build rc=0; lint rc=0; all seven focused suites green; harness
  PASS 19 / FAIL 0 / UNVERIFIED 2. No FAIL or UNVERIFIED in exercised behaviour.
- Pass 2 (no code changes between passes): release build rc=0; lint rc=0; all
  seven focused suites green; harness PASS 19 / FAIL 0 / UNVERIFIED 2.

The two UNVERIFIED are honest and not product defects: R2 is a process claim
(five-agent dispatch) that cannot be independently exercised from the finished
tree; R21 (PR) was pending at the time of the run and is completed by the
coordinator's git step.

## Auto-flags

- Changed test (corrected, not weakened): `WarmupGestureTests.swift` — see repair 4.
- No deleted or weakened frozen test.
- New local packages (no third-party dependency): `ClearlyInput`, `ClearlyStealth`,
  `FeatureIntelligence`.
- File changed outside the original agent plan: `AGENTS.md` (coordinator-only).

## Assumptions

- "21 requirements" = numbered items 1–21 in `.proof/requirements.md`.
- Offscreen snapshot rendering is the compliant headless screenshot path.
- The OS/client stealth capture matrix (Meet/Zoom/Teams × share mode) cannot be
  exercised headlessly; it is recorded as UNVERIFIED in `docs/stealth-compatibility.md`,
  never claimed as PASS.
