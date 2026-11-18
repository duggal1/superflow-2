# Requirements — extreme quality / performance / knowledge / recovery task

1. Launch 7 sub-agents with disjoint ownership, all given the design docs and strict no-smoke-test rules.
2. Aggressively test transcription quality: 200 deliberately-broken samples; 50-word, 140–150-word and larger tiers; multiple diverse domains; real S1-mini where feasible, honest NOT-EXERCISED otherwise.
3. Fix confirmed transcription defects (fact corruption in numbers, coordinates, clock times, final punctuation) — not weaken tests.
4. Make Island design brighter blue, ultra-sharp on the pixel grid, ultra-smooth at 60 FPS, with measured frame numbers and two screenshot passes.
5. Delete and rebuild the knowledge landing page from scratch with a real design; fix broken history line clamping / vertical breaking / inconsistent overflow.
6. Build a real SQLite-backed knowledge backend (CRUD, search, import/export, learning) with aggressive DB tests; front/back contract handshake.
7. Fix S1-mini reliability and speed (no silent fallbacks, thunder-fast on M1), audio loudness and a real VAD so the model gets clean loud speech; port good backend ideas from the `hex` repo to Swift.
8. Make crash recovery significantly better: atomic writes, checksummed journal, idempotent replay, crash-point tests.
9. Never freeze the user's Mac: one process at a time, build fence, GPU/CPU throttle, 5-minute kill caps, honest load monitoring.
10. Completion audit: two consecutive full passes with zero FAIL / zero UNVERIFIED and no code changes between; independent fresh-context review; then commit and push to main.

## Added: elite transcription-quality sweep (official S1-mini docs supplied)
11. Launch at least five read-only, light-weight sub-agents with very different angles on elite transcription quality, using the official superwhisper/s1-mini v1 model card as ground truth.
12. Agents must NOT freeze the Mac: no full builds, no `make verify`, no GGUF loads, no GUI, no repo writes; logs only in the opencode temp dir. Brutal analysis is still required.
13. Coverage: (a) exact prompt/control-line/thinking-off format fidelity, (b) brutal behavioral case testing against official examples, (c) pipeline order and integrity, (d) adversarial corpus coverage and weakened assertions, (e) integration/license fidelity.
14. Deliver a FAIL-first consolidated report with exact file:line evidence and an honest VERDICT per area.

Assumption: this is a continuation of the same overall quality sweep; state files are appended rather than archived because other agents are actively writing them in the shared working tree.
