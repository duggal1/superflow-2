# Plan: transcription quality fix (corrected)
## Root causes (verified)
- S1-mini trained on exact system prompt; any wording change degrades it.
  Prior prompt expansion was wrong — prompt must stay byte-identical.
- Deterministic LineFormat (capitalize + finalPeriod) overrides S1 styling:
  casual/semi-casual lowercase gets re-capitalized and punctuated.
- FormattingStage always list-shapes prose, overriding S1 Structure: prose.
- Pre-cleanup normalization order kept (model names before model).
## Files
- s1-prompt.json: REVERT to exact trained prompt + pinned hashes.
- TextPipelineBuilder: effective LineFormat from cleanupStyling.
- FormattingStage/shapeOutput: gate list shaping on cleanupStructure.
- Tests: styling preservation, structure gating, live S1 run.
## Verify: swift test TextPipeline/TextCleanup/LLMLlamaCpp + live model run.
