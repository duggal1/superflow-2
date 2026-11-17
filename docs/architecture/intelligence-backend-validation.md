# Intelligence / Dynamic Island backend validation (read-only)

Date: 2026-11-17. Scope: verify which requested capabilities already exist in code.
No UI was deleted or changed for this validation.

## Summary
The core backend **exists**: keystroke trigger, transcript buffer, screen OCR,
prompt modes, streaming assistant, Island bridge and history. Several requested
interactions are **only partially implemented or absent** — mostly input gestures,
defaults, and UI affordances, not the underlying AI pipeline.

| Requested capability | Status | Evidence |
| --- | --- | --- |
| Right Option opens Intelligence | Exists, but not exclusive | `KeyEventMapper.events` maps the configured `intelligenceTriggerKey` to `.intelligenceDown`; `AppCoordinator+Input.handleKeyEvent` routes it to `islandBridge.openAssistant`. Default is `.rightOption` (`selectedIntelligenceTriggerKey`). |
| Trigger locked to right Option only | **Missing** | `IntelligenceTriggerKey` has 4 cases and `IntelligenceTab` renders `allCases` in a `Segmented`; `intelligence.trigger` is user-selectable. |
| Assistant answers a typed question, Enter to send | Backend exists, UI absent | `MeetingIntelligence.ask(_:)`, `TranscriptBuffer`, `ReflectionClient.stream`. `IslandAssistantCard` has no `TextField` or Enter handling; it only shows Help/Retry/Go deeper. |
| Cmd+Option press-and-hold listening into the assistant | **Missing** | `KeyEventMapper` tracks command state but emits only `.rightCmdDown/.rightCmdUp`; no combined command+option listening event, no bridge into `assistantBuffer`. |
| Left Option tap/hold to send the transcript | **Missing** | `.leftOption` is an `IntelligenceTriggerKey` case only; no send action is wired to it. |
| Streamed answer in expanded Island, selectable/copyable | Partial | `IslandAssistantCard` renders `model.assistantAnswer` with `.textSelection(.enabled)` but caps it at 5 lines with a fade; it does not offer a Copy action in the card. |
| Screen awareness (ScreenCaptureKit + Vision OCR) | Exists, default off | `ScreenReader.swift` uses `SCScreenshotManager` + Vision; `MeetingIntelligence.submit` calls `screen.readText()` when `screenAware`. `MeetingIntelligence.screenAware` and `AppStorage("intelligence.screenAware")` default `false`. |
| Prompt themes: coding interview, sales, custom, normal | Exists | `MeetingMode` + `Prompts.modeLayer`. |
| Prompt theme: journal | **Missing** | No `journal` mode in `MeetingMode`. |
| Settings icon expands Island settings | **Missing** | `AssistantCard` has only a Dismiss button; no settings affordance. `IntelligenceTab` lives in the main window. |
| Start Meeting / continuous transcription | Exists via right-Command gestures | `GestureRecognizer.rightCmdDown/rightCmdUp` drives meeting start/finalize; `MeetingEngine` owns capture. No "Start Meeting" button in the Island. |
| Left Control toggles meeting start/end | **Missing** | `.leftControl` is only an `IntelligenceTriggerKey` case; meeting gestures are right-Command based. |
| 4–5 generated follow-up suggestions after a session | **Missing** | No suggestion-generation or suggestion-card code; `Prompts` has help/notes/question tasks only. |
| History inside the Island | Exists | `IslandPhase.history`, `HistoryPanel`, `.recent` and IslandFeed supply recent transcripts. |

## Blocking facts for the next (UI) phase
- The assistant is backed by the **Reflection API** (`ReflectionClient`, key in Keychain),
  not the local S1-mini/XPC helper. A key is required before any answer is produced.
- Screen OCR is implemented but headlessly unverified; a previous probe reached OCR
  but was interrupted (`agents/codex/meeting-intelligence/results/live-validation.md`).
- Current `S1-mini` cleanup and the Intelligence assistant are separate pipelines;
  do not assume S1-mini quality work improves assistant answers.

## Conclusion
The AI backend is substantially present. The missing pieces are interaction wiring
and defaults: locking the trigger to right Option, Cmd+Option hold-to-listen,
Left Option send, a text-entry field, default-on screen awareness, a journal mode,
an Island settings affordance, a meeting button/Left Control toggle, and suggestions.
