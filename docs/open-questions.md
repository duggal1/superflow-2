# Open questions

- **Type:** the UI is now SF Pro only, through `Typography`. The bundled `AlbertSans-Variable.ttf` remains in `App/Resources/Fonts` but is no longer selected by any view. Decide whether to delete the asset and its `ATSApplicationFontsPath` entry, or keep it as an unused fallback.
- **Visual verification:** light and dark, Increase Contrast, Reduce Transparency, Reduce Motion, window resizing (especially the 12-month grid past 1076 pt), pointer cursors, and Island drag/position persistence still need a run on a real display. `DESIGN.md` §16 lists the mechanical checks; the visual ones are not automated.
- **Core Audio / ScreenCaptureKit:** both meeting-capture paths are implemented and wired; device acceptance with Zoom and Meet remains unverified.
- **Diarization:** FluidAudio Sortformer is linked and wired into `AppEnvironment`; real-meeting speaker accuracy, echo handling and export quality remain unverified.
- **Waveform motion:** `WaveformView` is now the only drawing path. The 30 fps canvas and the 700 ms idle stop have not been profiled on an Intel Mac.
- **Contribution-cell radius:** still a local `2 pt` value in `ContributionGrid`; it is documented there but is not a shared `Radius` token.

## Addendum A (2026-10-27)

- **Icons — blocking the next UI phase:** Addendum A §37 and `PLAN.md` §18.2 require
  Hugeicons for every control. `DESIGN.md` §7 requires SF Symbols only. The repo
  currently uses Hugeicons in the sidebar and SF Symbols in system menus. Choose
  one system before Phase 7c; do not migrate icons on the strength of one clause.
  Conservative default until answered: keep the existing wrapper and introduce no
  second icon set.
- **Meeting audio retention:** 7 days by default, about 230 MB per hour for two
  sources. Confirm 7 days, or choose shorter, longer or off. Learned rules and
  review re-pass depend on retained audio.
- **Spike J corpus:** candidate-rule precision and chapter quality cannot be
  measured from the repo. A small consented set of real meetings is needed
  (two-person, four-person, overlap, echo, long monologue, decisions/actions).
  Until then every candidate rule ships disabled and chapters are labelled
  heuristic.
- **Marker hotkeys:** defaults depend on Spike F, which has not run. Until the
  chords are confirmed the Island should show the marker buttons without
  advertising an unverified global chord.
- **Agent Bridge and MCP:** off by default, per-meeting or per-folder sharing.
  Confirm the default, and name the agents used for the compatibility test
  (Claude Code, Cursor, Codex, other). The MCP spec is now 2026-07-28 and most
  installed agents still speak an `initialize`-based revision; the server must
  support both (ADR 0017).
- **Voice memory:** off by default. FluidAudio exposes speaker embeddings, but
  stability, threshold and deletion have not been measured (ADR 0018).
- **Auto-activate safe learned rules:** off by default; Suggest only. Confirm.
- **Optional local analyzer:** skipped for v1 (ADR 0016). Confirm.
- **MeetingExport extraction:** `MeetingEngine` still owns export
  (`schemaVersion: 1`). Phase 7b moves it to the L2 `MeetingExport` package and
  adds the recording-path isolation rule. Confirm there are no external
  consumers of the current API before the move.
- **Build gate — resolved 2026-10-27:** `make verify` passes in full. Keep it
  green after every addendum phase; a red gate still blocks a phase exit.
- **Code Speak vocabulary:** the first cut ships off by default with the command
  list in ADR 0020. Confirm the trigger phrases (case styles, `backtick`,
  `code block`, bracket pairs, `arrow`) and the single-word identifier
  allowlist before enabling it by default, using real dictation.
- **Context profile mappings:** the bundle/host lists in `ContextProfiles` are a
  first pass (Xcode/VS Code/Terminal, Slack/Discord, ChatGPT/Claude, Notes/Word).
  Trim or extend them before detection is wired in Phase 7c; unknown apps fall
  back to Writing.
