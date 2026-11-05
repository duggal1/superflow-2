# Dictation delivery and cleanup reliability plan
Date: 2026-11-05. Branch: dictation-paste-cleanup-regressions. No checkout, reset or force push.

## Verified problems
1. TextInsertionService maps a dispatched but AX-unverifiable paste to notInserted; IslandBridge then emits pasteFailed even if the target accepted the paste.
2. SessionCleanupCoordinator abandons pending S1-mini work after 2.5 s without applying deterministic deduplication, paragraph/list formatting, normalization, or spacing to the affected raw rows.
3. Cleanup defaults to an unconditional lists prompt; this biases ordinary prose instead of selecting lists from explicit speech cues.
4. There is no user-visible proof of real S1-mini invocation, acceptance, timeout or fallback.
5. Current main CI fails IslandPanelControllerTests:64; fix it only if the focused regression change can be proven.

## Implementation
- Treat an accepted keyboard/menu/AX mutation as attempted insertion even when AX cannot verify it; preserve the recovery clipboard, never call it verified, never re-paste automatically and never trigger a false failure card.
- Add a regression with an unverifiable-but-posted paste, a genuine no-target failure, and a verified insertion; keep Island silent on attempt/success and expose copy text only for definite failures.
- Add a deterministic-only TextPipeline path (no S1-mini call). At cleanup timeout, run it for unfinished segments, persist fallback text before insertion and block late model writes from overwriting that fallback.
- Guarantee deduplication and punctuation/paragraph/list whitespace for both model-cleaned and timed-out speech without altering quoted identifiers, protected tokens, number sequences or deliberate emphasis.
- Make prose the default S1 structure, automatically select lists on strong spoken cues and preserve explicitly chosen list mode.
- Add an opt-in Developer mode control in Advanced Settings, showing the real latest S1-mini start, accepted, failed, deadline or skipped status from transcript-free metrics.
- Maintain no-telemetry, no-transcript-in-logs privacy, full copy recovery, and fast paste latency.

## Gates
- Focused tests for attempted vs verified insertion, failed paste Island state, dedupe over repeated phrases, list/paragraph formatting, cleanup queue timeout, no late overwrite, and Developer status.
- Inspect Nov 3–4 related commits against main rather than resetting files.
- Compile Swift on macOS CI, fix errors in changed code; run relevant tests and required CI before merging.
- Real on-device S1-mini quality, paste in a native editor + Chromium, and subjective 10/10 rating remain unverified without local hardware/fixtures.
