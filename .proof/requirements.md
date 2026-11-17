# Requirements — Dynamic Island intelligence rebuild

1. Read rules.yaml, git.yaml, DESIGN-RULES.MD, DESIGN.md, DYNAMIC-ICELAND-DESIGN.MD, dynmaic-island-intelligence.md, and docs/architecture/intelligence-backend-validation.md before editing.
2. Launch five sub-agents, each given the design documents to read, with disjoint file ownership.
3. Delete the current Island UI layer and rebuild it clean; keep and reuse the existing backend (transcription, Reflection streaming, prompts, screen OCR, history, waveform renderer) behind a thin view model.
4. Declare one token set (Tokens.swift: type, spacing, radii, colors, durations) before any view; no magic numbers elsewhere.
5. Build a pure enum + reducer state machine first: collapsed → compose → listening → thinking → answer; collapsed → meetingLive → meetingEnded(suggestions) → answer; any → history/settings; defined entry, exit, error/permission variants.
6. Attached top-center borderless non-activating NSPanel: notched Macs use safeAreaInsets/auxiliary areas, non-notch shows a pill; all Spaces, fullscreen, no focus steal except text field; frame never animates, silhouette morphs as one continuous shape.
7. Right Option is the ONLY trigger: hold = listening with pixel waveform, release = send; quick tap (<250 ms) latches, next press sends; any other key cancels; Left Option and Right Control do nothing; Option+key typing still works elsewhere.
8. Delete the trigger-key picker from settings; migrate/clear stored trigger preference.
9. Left Control toggles continuous meeting start/end; transcription on by default; question detection with an exposed sensitivity constant; silence produces nothing; end shows 4–5 clickable suggestion rows that answer; meeting saved to History.
10. Typed input: click collapsed Island, placeholder "Enter any data and press Enter", Enter sends, streamed answer, Copy, Esc collapses.
11. Messy-transcript intent extraction in ONE reusable system prompt block shared by PTT and meeting mode; ignore fillers/speaker labels, infer intent, use screen context, answer directly.
12. Screen reading on by default; capture per send (Island excluded); Vision OCR fallback; inline permission state with Settings link; answers continue without screen context.
13. Prompt/theme selector enumerates every existing prompt/theme from source (including Coding Interview, Sales Call, Journal/Personal, General Meeting); nothing hardcoded or dropped; selection persists.
14. Settings icon expands Island in place; port every old setting except key picker; grouped Capture/Model/Prompts/Permissions/About; permission states with fix buttons.
15. History is an Island state: list, open full transcript+answers, search, delete, Copy.
16. Output view: fully expanded, selectable/copyable text, Markdown with copyable code blocks, scrolls inside Island, capped height.
17. Stealth: Island visible to user but excluded from Google Meet/Zoom/Teams share; NSWindow.sharingType = .none enforced on every app window; no private APIs; verifier with positive control; honest Verified/Failed/Unverified status; WindowServer sharing-state dump script; compatibility matrix docs/stealth-compatibility.md.
18. All testing headless: native apps launched background/hidden, no user focus, no global keystrokes, screenshots only of app window, drivers in tools/, JSON out, documented in tools/README.md.
19. Aggressive testing: every requirement happy path, edges, hostile input, repeated actions, all states, aftermath; two screenshot review passes with fixes; completion audit two consecutive clean passes.
20. Existing functionality must not regress; build, lint, focused tests and make verify green except documented pre-existing stale test.
21. Commit/push per git.yaml (6–12 word messages); open a PR and do NOT merge.
