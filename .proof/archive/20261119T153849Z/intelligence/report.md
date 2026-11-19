# Agent 4 — Intelligence surface behind the Dynamic Island

STATUS: DONE (with two integration gaps owned by other agents; listed below)

## What was delivered

A new module `SuperflowFeatureIntelligence` exposing:
- `IntelligenceIslandModel` — `@MainActor @Observable`, thin, with all IO behind
  two injected seams (`IntelligenceAnswerServing`, `IntelligenceHistoryServing`).
- `IntelligenceContent` — a SwiftUI view Agent 1 hosts for the compose / answer /
  settings / history / suggestions Island states. It uses shared design tokens and
  shared controls only (no raw `Button`, `TextField`, popover or menu).
- `IntelligencePrompts.messyTranscriptBlock` — ONE shared messy-ASR block embedded
  exactly once by `askTask`, `meetingDetectionTask` and `suggestionsTask`.
- `IntelligenceQuestionDetector` with public `sensitivity` constant.
- `IntelligenceTheme.allFromSource()` — enumerates `MeetingMode.allCases`; no
  hardcoded prompt list; a derived label handles any future source case.

Existing backends are wrapped, not rewritten:
- `ReflectionAnswerService` streams through the existing `ReflectionClient`,
  reads screen context via the existing `ScreenReader` (on by default), snapshots
  the existing `TranscriptBuffer`, and builds prompts with `Prompts.system/user`.
- `RepositoryHistoryStore` does list/search/open/delete through the existing
  `TranscriptRepository` (no new store or schema).
- `IntelligenceIslandSeam.makeMeetingIntelligence()` builds the existing
  `MeetingIntelligence` with the selected mode, effort and screen-aware default.

App wiring (all headless; no windows opened):
- `AppEnvironment.intelligenceIsland` owns the seam; copy goes through the
  existing `SystemTextInserter` (clipboard strategy).
- `AppCoordinator+IntelligenceIsland.swift` routes open/submit/copy/settings/
  history/suggestions.
- `IntelligenceIslandSeam` conforms to Agent 1's `IslandIntelligenceSeam`
  protocol (`composeView`/`answerView`), bridging content and send/copy callbacks.

## Tests / results (headless)

- `swift test --package-path Packages/L3-Features/FeatureIntelligence`
  → 14 tests, 0 failures (prompt parity, shared block, question detection with
  sensitivity, compose→streamed answer→copy, blank input, messy transcript,
  meeting question detection, theme persistence, settings in place, history
  CRUD/search/open/copy, suggestions→answer).
- `swift test` in `.proof/intelligence/verify` (isolated package running the exact
  five `App/SuperflowApp/Tests/SuperflowAppCoreTests/HeadlessIntelligence*.swift`
  files with fakes) → 21 tests, 0 failures. The isolated runner exists because
  the full App package build was still broken by other agents' in-progress edits
  (see Unresolved); it was used only as a test harness, never as production code.
- Two consecutive clean passes of both suites with no code changes between.
- `tools/check-deps`: "Dependency layers are valid."
- `tools/lint-forbidden`: zero violations in files owned by this agent.
- No GUI, no window, no screenshot: headless-only was an explicit constraint.

To reproduce the AppCore headless tests in place once the App builds:
`swift test --package-path App/SuperflowApp --filter HeadlessIntelligence`

## Files changed

New module:
- `Packages/L3-Features/FeatureIntelligence/Package.swift`
- `.../Sources/SuperflowFeatureIntelligence/IntelligenceTypes.swift`
- `.../IntelligencePrompts.swift`
- `.../IntelligenceBackends.swift`
- `.../ReflectionAnswerService.swift`
- `.../RepositoryHistoryStore.swift`
- `.../IntelligenceIslandModel.swift`
- `.../IntelligenceContent.swift`
- `.../IntelligenceContentPanels.swift`
- `.../Tests/FeatureIntelligenceTests/IntelligenceFakes.swift`
- `.../IntelligenceCoreTests.swift`, `.../IntelligenceModelTests.swift`

App:
- `App/SuperflowApp/Sources/SuperflowAppCore/AppEnvironment.swift` (edited)
- `App/SuperflowApp/Sources/SuperflowAppCore/IntelligenceIslandSeam.swift` (new)
- `App/SuperflowApp/Sources/SuperflowAppCore/AppCoordinator+IntelligenceIsland.swift` (new)
- `App/SuperflowApp/Package.swift` (additive: FeatureIntelligence package + product
  in AppCore and test targets; coexisting with Agent 2's additions)
- `App/SuperflowApp/Tests/SuperflowAppCoreTests/HeadlessIntelligenceFakes.swift`
- `.../HeadlessIntelligenceComposeTests.swift`
- `.../HeadlessIntelligenceHistoryTests.swift`
- `.../HeadlessIntelligencePromptTests.swift`
- `.../HeadlessIntelligenceUtteranceTests.swift`

Report-only harness (not production):
- `.proof/intelligence/verify/Package.swift` + copied HeadlessIntelligence test files

No git writes, no commits, no changes to `.proof/requirements.md` or
`.proof/progress.md`.

## Unresolved (hand to coordinator / other agents)

1. **Journal/Personal prompt missing from source.** `MeetingMode` in
   `Packages/L2-Engines/MeetingIntelligence/.../Prompts.swift` currently has only
   `normal, codingInterview, sales, custom`. The selector enumerates the enum, so
   it cannot show a mode the backend does not define. Adding a `journal` case must
   be done by that backend's owner; my selector will then include it automatically
   with the derived label "Journal". `.custom` is currently labelled
   "Personal / Custom" so the personal use case is already reachable. I did not
   edit the backend (explicitly out of scope).
2. **Agent 1 must inject the seam into `IslandRoot`.** Its `IslandRoot` still
   hardcodes `@State ... = LocalIntelligenceSeam()`. Once it accepts an injected
   `any IslandIntelligenceSeam` (my `IntelligenceIslandSeam` conforms), the Island
   renders my compose/answer views. Settings/history/suggestions are hosted via
   `AppCoordinator.intelligenceContent(for:)`.
3. **Full App package build/test blocked during this run** by Agent 2's
   `SuperflowClearlyInput` module resolving intermittently plus clang dependency
   scanning failures under concurrent builds. The new HeadlessIntelligence tests
   were therefore verified in the isolated harness above (same source files).
   Re-run the in-place command once the App package is green.

## Assumptions

- "Enumerate every existing prompt from source" means `MeetingMode.allCases`,
  not a hardcoded list; task prompts (`help`, `notes`, `question`) are instructions,
  not selectable themes.
- Answers remain memory-only in the model; "open full transcript+answers" merges
  in-memory answers with the store-backed transcript (the existing contract has no
  answer persistence).
- Island history uses the existing `TranscriptRepository`, so deletion is a real
  session delete (no second database).
