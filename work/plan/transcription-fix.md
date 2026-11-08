# Plan: transcription quality fix (part one only)
## Root causes (verified in code)
- `s1-prompt.json` system prompt is generic; no fidelity, disfluency, or
  terminology rules, so S1-mini under-edits and can invent names.
- `TextPipelineBuilder` runs S1-mini cleanup before `ModelNameStage` and
  `TechDictionary` normalization, so corrupted names reach the model first.
- `vocab_v4.json` lacks Raspberry Pi, HomePod, Blender, Codex entries and
  `nextgs`/`next gs` aliases; Tier B gate needs dev context.
- No deterministic spacing/`II` fix or sentence-level seam dedupe.
## Files
- `s1-prompt.json`: editorial + fidelity contract in system prompt.
- `TextPipelineBuilder.swift`: pre-cleanup model-name + Tier-A tech dict,
  deterministic repair stage pre/post.
- `TranscriptionRepair` (new file in TextPipeline): `.Hey` spacing, `II`→`I`,
  repeated-sentence dedupe.
- `vocab_v4.json` + provider regen inputs: add general entries/aliases.
- Tests: pre-normalization, repair, gate.
## Verify: `swift test --package-path Packages/L2-Engines/TextPipeline`
plus TextCleanup, Lexicon, catalog packages.
