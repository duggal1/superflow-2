# Brutal S1-mini quality — final report

## Method
Headless, opt-in, loopback-only Python driver (`tools/brutal-s1/brutal_s1.py`) driving
the installed `s1-mini-q4_k_m.gguf` through `llama-server` with the repo's exact pinned
system prompt and control line, greedy decoding, `--jinja` and
`--chat-template-kwargs '{"enable_thinking":false}'`. 21 synthetic, deliberately broken
transcripts. No model download, no user corpus, no GUI. Run: `brutal_s1.py --i-opt-in`.

## Raw model result (final run)
- 11/21 cases pass the strict raw-output gate.
- Latency p50 ~473 ms, p95 ~596 ms; streaming time-to-first-token p50 ~41 ms.
- No token-cap hits, no request errors.

Raw failures are mostly *model* behaviours the app already repairs downstream:
missing final period, `March 3rd`, duplicated `backend/backend` path, inline dash
lists and pseudo-decimals. Filler-only returns "Okay, basically" rather than empty —
model choice, not a guard failure.

## App-delivered result (real production stages, offline proof)
`BrutalFormattingProbeTests` feeds the measured raw completions into the real
post-model pipeline:
- final period, `March 3, 2026`, `S1-mini`, and the card list are repaired already;
- `next.js` -> `Next.js` is repaired by the full pipeline;
- the four broken list renderings (glued `-word`, `Bullet,` commas, `0.1/0.2/0.03`
  pseudo-decimals, spoken `point one/two/three`) survived downstream before this
  change and now render as proper `- item` Markdown bullets.

`testCleanGuardAcceptsRealS1Completions` runs the production `CleanGuard` on real
measured outputs: every tested output is accepted, i.e. S1 output is used and does
not trigger the raw-text fallback. Existing proof `.proof/quality/extreme-8-cases.txt`
shows `STATE: cleaned` for all eight extreme real-model cases.

## Changes
- Added `SpokenMarkerListShaper` (layout-only, word-preserving) wired into `shapeOutput`.
- `EnumerationDetector` now hints `lists` for spoken separators (`dash`, `hyphen`,
  `bullet`, `star`) so S1 receives the right Structure value.
- Added 10 regression tests (shaper/detector + downstream + guard acceptance).

## Verification
- Targeted tests: 10/10 pass.
- Full `TextPipeline` suite: 160 tests, 1 skip, 1 failure —
  `ReferenceCleanupTests.testReferenceCodingDictationTier0`. Confirmed pre-existing:
  the identical failure occurs with this task's source changes temporarily replaced
  by clean HEAD. Its input is `hero dot t s x no wait hero.tsx` (spoken first value),
  which the code-repeat resolver does not cover. Left untouched as out of scope.
- Disk: ~9.7 GiB free throughout; no full App build, no llama XCFramework download.

## Honest verdict
S1-mini is being used (not falling back), is fast, and the delivered text is
high quality after the deterministic repairs. Raw model output still needs those
repairs for list formatting and a few cosmetic details; that is the designed
division of labour in this pipeline.
