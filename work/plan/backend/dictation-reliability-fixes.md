# Dictation reliability: insertion, warm start, GPU, gestures

Owner report: paste never lands despite permissions; launch shows “Loading model” for
20–30 s; cleanup is falling back instead of using the GPU; fn double-tap/hands-free and
the right-⌘ meeting gesture fail, probably because another dictation app owns fn.

Work P1 → P4 in order. Each phase gets its own focused test run and commit.

## P1 Insertion (paste path)

Evidence:
- `AXRoleClassifier.nonEditableRoles` includes `AXApplication`, `AXList`, `AXTable`,
  `AXRow`, `AXCell`, `AXColumn`, `AXOutline`. Apps that report the application or a
  table container as the focused element bail out before the paste is ever posted.
- `CGEventPastePoster` posts at `.cghidEventTap`. The reference implementation that
  worked posted at `.cgSessionEventTap`. `TextInsertionOptions.postTap` exists but is
  never wired into the poster.
- `pasteAttempt` gives up after one unobserved chord; there is no alternate-tap retry.

Changes:
- Only unambiguously non-text controls stay `.notEditable`; containers (`AXApplication`,
  lists, tables, rows, cells, columns, outlines) become `.unknown` so paste is attempted.
- Default synthetic chord posts at `.cgSessionEventTap`; wire `options.postTap` through
  `PasteEventPosting`.
- On an observed “nothing” with a usable AX baseline, retry once at the alternate tap
  (`.cghidEventTap`), then verify again. Never retry without a baseline (double-paste risk).
- Regression tests: role classification, option default, alternate-tap retry, no retry
  without baseline.

## P2 Warm start and GPU

Evidence:
- `SessionEngine.warmUp()` sets `.warming` at launch; the window maps that to
  “Loading model”, and `MenuBarController.startDictation` refuses while `.warming`.
- Warm-up starts after settings, DB maintenance, transcript purge and pipeline rebuild.
- ASR load, VAD load and cleanup-model load are serialized; the dummy ASR prediction
  processes 4 s of silence.
- Stored settings still contain `cleanupCompute: "cpu"` even though the product default
  is GPU; recent sessions all show `cleanup_state = fallback`.
- `HarperChecker` is built with `HarperConfig()` (`enabled = false`) even when
  `settings.harperEnabled` is true, so Harper can never run.

Changes:
- Add a silent `SessionEngine.prewarm()` that loads the model without entering
  `.warming`. Launch uses it; only a real session-triggered load shows warming.
- Start ASR prewarm immediately after settings load, in parallel with DB/pipeline work;
  start cleanup-model preparation in the same window.
- Load ASR and VAD concurrently; reduce the dummy prediction to just over the largest
  streaming chunk.
- `MenuBarController` waits for an in-flight load instead of refusing fn; gestures stay
  live through warm-up.
- One-time migration of the stored `cpu` value to GPU (persisted in settings JSON).
- llama.cpp: 3 sessions (matches default cleanup workers), parallel session warm-up,
  explicit thread counts, bounded batch/ubatch.
- Wire `settings.harperEnabled` into `HarperConfig`.

## P3 Gestures

Evidence:
- Double-tap races the 10 ms tick: a tick that fires just before a short `fnUp` puts the
  recognizer in `.pushToTalk`, so the release submits instead of waiting for the second tap.
- Right-⌘ down/up is inferred from the shared Command flag, so a right-⌘ release while
  left-⌘ is held looks like another down.
- No detection of competing dictation apps; a later-installed fn tap can win event order.
- `.warming` refusal made fn look dead during launch.

Changes:
- `fnUp`/`rightCmdUp` decide tap-vs-hold from the event timestamp, not only current state.
- Track physical key state for right-⌘ instead of the shared flag.
- Reinstall the passive tap on a slow health cadence so it stays at the head of the tap
  chain after another app installs its own.
- Detect known competing dictation apps while fn is the dictation key; terminate them
  gracefully and report it. Narrow allowlist, graceful `terminate()` only.
- Tests for the tick race, right-⌘ with left-⌘ held, and conflict allowlist matching.

## P4 Parallel Harper

Evidence:
- `HarperFFILinter` is one actor with one C handle, so long text lints serially.
- The Rust FFI keeps dictionary/group state per handle, so separate handles are safe.

Changes:
- Split long text at sentence boundaries (UTF-16 offsets), lint up to 3 chunks on separate
  cached handles in parallel, merge/sort/dedupe offsets.
- Short dictation keeps the single-handle fast path.
- Tests: chunk planner boundaries/offsets, merged lint offsets, single-chunk fast path.

## Verification

- `swift test --package-path Packages/L1-Adapters/TextInsertion`
- `swift test --package-path Packages/L1-Adapters/HotkeyEngine`
- `swift test --package-path Packages/L2-Engines/GestureKit`
- `swift test --package-path Packages/L2-Engines/SessionEngine`
- `swift test --package-path Packages/L1-Adapters/ASRFluidAudio`
- `swift test --package-path Packages/L1-Adapters/GrammarHarper`
- `swift test --package-path Packages/L1-Adapters/LLMLlamaCpp`
- app build, `make lint`; `make verify` after stabilization.
- Manual/runtime checks: paste into a native text field and a Chromium editor; cold and
  warm launch timing from the `ModelWarmup` log; fn tap/double-tap/right-⌘ hold.
