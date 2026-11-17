# Independent review — Dynamic Island intelligence rebuild

Fresh-reviewer posture: I did not build this. A green build, a source grep or a
single happy path is **not** evidence. Anything partial, smoke-only, unverified,
weaker than a sibling feature, or outside the request is FAIL. `UNVERIFIED` is
never `PASS`.

Final snapshot reviewed: commit `f81aa29` on `main`, working tree with new
packages wired in, most of the old Island UI deleted, a **green compile** but a
**red lint and a red focused test suite**. Two frozen tests were deleted or
weakened (auto-flagged below). Four implementing agents were still editing at
the time of this review.

| # | Requirement | Grade | Evidence / why |
|---|-------------|-------|----------------|
| 1 | Read all 7 governing docs before editing | **PASS** | All seven files present; I read them in full this session (line counts in `logs/check-01.log`). Process evidence only — it does not prove the other agents read them. |
| 2 | Five sub-agents, disjoint ownership | **FAIL** | Only evidence is a self-authored line in `.proof/progress.md`. No ownership manifest, no `agent/*` branches, no commit per agent. Unverified process claim → FAIL. |
| 3 | Delete old Island UI layer, rebuild clean, reuse backend | **FAIL** | 12 old Island UI files are deleted (`IslandAssistantCard`, `IslandCard`, `IslandHistory`, `IslandIdle`, `IslandLiveLine`, `IslandMarks`, `IslandMeetingDiscard`, `IslandMeetingPanel`, `IslandNoticeCard`, `IslandPasteFailed`, `IslandStage`, `IslandTransitions`, `IslandWings`), but `IslandModel.swift` and `IslandReducer.swift` remain beside the new `IslandFlow` / `IslandShell`. Partial rebuild, and no runtime proof of the new structure. |
| 4 | One `Tokens.swift`, no magic numbers elsewhere | **FAIL** | `Tokens.swift` now compiles, but `make lint` reports 3 forbidden raw-font violations, e.g. `FlowContent.swift:200 .font(.system(size: IslandTokens.Size.glyph))`, `ComposeAndAnswer.swift:29/36/63/99/106`. One token set is declared; raw font construction leaked into views. |
| 5 | Pure enum + reducer state machine first | **FAIL** | `IslandFlow.swift` defines the required cases (`collapsed`, `compose`, `listening`, `thinking`, `answer`, `meetingLive`, `meetingEnded(suggestions)`, `history`, `settings`, `error`, `permission`). But the old reducer/model coexist, and no successful transition-test run was shown for the new machine. Source-only → FAIL. |
| 6 | Attached top-center borderless non-activating NSPanel, safe-area geometry, all Spaces, static frame | **FAIL** | Source has `.borderless`, `.nonactivatingPanel`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `sharingType = .none`, `safeAreaInsets`, `setFrame(…display:false)`. No runtime proof of Space/fullscreen/focus behaviour. `external-live.png` shows a much smaller wing than pass 1; fit with real live text unproven. |
| 7 | Right Option only; hold/release, tap-latch, other keys cancel | **FAIL** | `ClearlyInput/RawKeyEventMapper.swift` maps keycode 61 / bit `0x40`; `Gesture.swift` has `holdThreshold = 0.25`. `GestureKit` unit tests pass (21/21) but those are the **old** gesture suite; no successful run of the new `ClearlyInput` gesture tests was demonstrated and no `CGEvent.postToPid` proof that Left Option / Right Control / Option+E are inert. |
| 8 | Delete trigger picker; migrate/clear stored preference | **FAIL** | Picker symbols gone from `IntelligenceTab.swift` and `AppCoordinator+Input.swift` no longer reads `intelligence.trigger`. Source-only; no runtime proof the stale key is cleared on launch. FAIL for lack of exercise. |
| 9 | Left Control meeting toggle, default-on transcription, sensitivity constant, silence→nothing, 4–5 suggestions, saved to History | **FAIL** | `IntelligenceIslandModel.swift` has `suggestions` + `suggestionsTask()`; no exposed question-sensitivity constant found. Pass-2 screenshot `notch-meeting-panel.png` **regressed** to a collapsed wing — the expanded panel with stats/legend/End meeting is gone, and `IslandWaveformWiringTests.testListeningPaintsBlueCellsInTheRightWing` now fails ("meter drew no lit cells"). FAIL. |
| 10 | Typed input: exact placeholder, Enter, streamed answer, Copy, Esc | **FAIL** | Exact placeholder present at `IntelligenceContent.swift:44`. No UI was driven (no app launch) and no focused test for the compose→answer flow was shown. Source-only → FAIL. |
| 11 | One shared messy-transcript intent prompt for PTT + meeting | **FAIL** | `IntelligencePrompts.swift` has a shared block (fillers, speaker labels, intent, screen text) used by `askTask`/`suggestionsTask`/`system`. No compile/test proof both PTT and meeting paths call it. Unverified → FAIL. |
| 12 | Screen reading **on by default**, Island excluded, OCR fallback | **FAIL** | Direct contradiction: `MeetingIntelligence.swift:14` is `@Published public var screenAware = false`. `ScreenReader.swift` + `ScreenCaptureExclusion.swift` exist but the default is off. Clear FAIL. |
| 13 | Prompt/theme selector enumerates every source theme (incl. Coding Interview, Sales Call, Journal/Personal, General Meeting) | **FAIL** | `Prompts.swift:3`: `case normal, codingInterview, sales, custom`. No `journal`/Journal-Personal and no explicit General Meeting case. Required themes absent. |
| 14 | Settings icon expands Island in place; all old settings; groups Capture/Model/Prompts/Permissions/About | **FAIL** | `IntelligenceContentPanels.swift` has only `Prompts`, `Capture`, `Model` headings. `Permissions` and `About` absent; full settings port not demonstrated. Partial → FAIL. |
| 15 | History as an Island state: list/open/search/delete/Copy | **FAIL** | `screens/pass1/notch-history.png` renders a history panel, but search/delete/open-full were never exercised, and pass-2 regressed the meeting panel. FAIL. |
| 16 | Output view: selectable, Markdown with copyable code blocks, scroll, capped | **FAIL** | `.textSelection(.enabled)`, `ScrollView`, `.frame(maxHeight: …)` exist in `IntelligenceContent.swift`. Zero matches for Markdown / fenced code / copyable code blocks in `FeatureIntelligence/Sources`. Required feature absent. |
| 17 | Stealth: sharingType `.none` every window, verifier + positive control, honest status, dump script, compatibility matrix | **FAIL** | Source improved: `ClearlyStealth` has verifier/status/WindowGuardCore/exclusion, `docs/stealth-compatibility.md` now exists (4592 B), no private-API hits. But no SCK positive-control run was demonstrated and the honest-status path is unverified at runtime. UNVERIFIED core → FAIL. |
| 18 | All testing headless, drivers in tools/, JSON out, documented | **PASS** | Verified directly: harness + README + two compiled Swift drivers; no `open -a`, global keypress, or cursor movement; 69 PNGs produced offscreen across two passes without launching a GUI; `IslandUIDriver` output is JSON. |
| 19 | Aggressive testing, two screenshot passes with fixes, two clean completion passes | **FAIL** | Two image sets exist (42 pass-1, 27 pass-2) and 7 fix requests are documented, but pass 2's suite is **red** (waveform regression) and the expanded meeting panel regressed. No two consecutive clean passes; two frozen tests were deleted/weakened. FAIL. |
| 20 | No regression: build, lint, tests, make verify green | **FAIL** | Island build green (2.06 s), `GestureKit` 21/21, `MeetingIntelligence` 5/5, but `make lint` reports 3 forbidden-pattern violations and `FeatureIsland` suite fails `testListeningPaintsBlueCellsInTheRightWing`. Frozen tests deleted/weakened (see flags). FAIL. |
| 21 | Commit/push per git.yaml; open a PR and do NOT merge | **FAIL** | `git branch -a` shows no `agent/*` branches, `gh pr list --state open` returns `[]`, HEAD is `f81aa29` on `main`. No PR → FAIL. |

## Grade summary

**PASS 2/21 (R1, R18) · FAIL 19/21.**

## Auto-flags (items to justify)

- **Deleted frozen test:** `Packages/L3-Features/FeatureIsland/Tests/FeatureIslandTests/IdleLampMotionTests.swift` (84 lines) — deleted from the working tree. It asserted the idle lamp animation advances and that Reduce Motion keeps it still.
- **Weakened frozen test:** `IslandSnapshotTests.swift` — 23 lines removed, including the whole `testLongCancelledTranscriptKeepsUndoInsideTheContentGutter()` with its `XCTAssertLessThanOrEqual(right, contentRight)` and `XCTAssertGreaterThan(right-left, 70*scale)` assertions. Test coverage was reduced, not added.
- **Changed frozen test:** see the two above; both are `git diff HEAD -- '*Tests/*.swift'` findings.
- **New dependency:** three new local Swift packages — `ClearlyInput`, `ClearlyStealth`, `FeatureIntelligence` — now wired into `App/SuperflowApp/Package.swift`. No third-party dependency added.
- **File changed outside owner scope:** `AGENTS.md` (coordinator-only, 523 lines removed). The validation agent edited no source file, no `requirements.md`, no `progress.md`.

These test deletions/weakenings violate `rules.yaml` (`tests_first`: never edit tests to make them pass) and must be restored or justified before any PASS claim.
