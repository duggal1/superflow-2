# Engineering dictation vocabulary

## Root cause

The bundled post-ASR lexicon lacks several observed engineering aliases, and the pinned Nemotron 3.5 manager is not given any acoustic vocabulary. The final transcript alone cannot establish why its negation and status code differ from the read-aloud script.

## Goal

Improve recognition of a small set of distinctive engineering terms and add context-gated deterministic corrections for the supplied transcript variants.

## Non-goals

- Do not change S1-mini, its pinned prompt, cleanup guards, deadlines, or fallback behavior.
- Do not rewrite negation, status codes, or ambiguous phrases such as “localos” without audio evidence.
- Do not claim a 9/10 quality result without recorded audio and human references.

## Invariants

- Keep the Nemotron vocabulary small and avoid common or short homophones.
- Gate ambiguous post-ASR aliases on nearby technical context.
- Preserve unverified numbers, negation, and valid everyday text.

## Steps

1. Add positive and negative dictionary acceptance cases; verify the positives fail before catalog changes.
2. Add a conservative Nemotron vocabulary and context-gated catalog aliases.
3. Run the TextPipeline dictionary tests and ASR adapter tests.
4. Review the diff and retain the missing-audio quality limit in issue tracking.

## Files

- `Packages/L1-Adapters/ASRFluidAudio/Sources/SuperflowASRFluidAudio/NemotronMultilingualStreamingEngine.swift`
- `Packages/L2-Engines/catalog/vocab_v4.json`
- `Packages/L2-Engines/TextPipeline/Tests/TextPipelineTests/DictionaryEvalTests.swift`
- `docs/STATUS.md`
- `issue.md`

## Verification

- Red before catalog changes: all seven new technical-alias cases failed.
- Green: the TextPipeline dictionary suite passed 4/4; the ASR adapter recognizer suite passed 10/10 and compiled the pinned custom-vocabulary API.
- Limitation: no recorded audio was supplied, so real ASR recall, false-fire rate, latency impact, and S1-mini grammar quality remain unmeasured.
