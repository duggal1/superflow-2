# Plan: always accept S1-mini, split formatting responsibilities

## Root cause (evidence so far)
- Real S1-mini produces correct grammar, bullets and self-corrections headlessly.
- `CleanGuard.verify` rejects those outputs and `CleanupService` falls back to raw:
  numeric formatting (`200ms`/`200 ms`, `4 bit`/`4-bit`), apostrophe normalization,
  casing changes and long-text lemma heuristics were treated as content loss.
- Deterministic stages then format the raw text, so S1's work is never seen.

## Changes
1. Diagnose the remaining backend rejection exactly (no guessing).
2. Split responsibilities: S1 owns grammar, punctuation, bullets, self-corrections.
   Deterministic stages own facts, numbers, identifiers, protected terms — after S1.
   Remove pre-cleanup passes that protect literals before the model.
3. Narrow `CleanGuard` to hard invariants: negation, quantifiers, magnitude words,
   digit runs, paths, non-empty and no tail loss. Formatting/casing/lemma churn cannot
   cause fallback. Keep zero retry loops.
4. Scale the interactive deadline with input tokens so long dictation is cleaned, not
   dropped. Short utterances keep the fast path.
5. Raise and brighten the pre-ASR audio chain for clearer, louder VAD/ASR input.
6. No sentence-specific rules; all fixes must be general.

## Verification
- Headless end-to-end with real S1-mini on both user transcripts and previous cases.
- Focused guard/cleanup/TextPipeline/AudioCapture/Enhancement tests, then `make verify`.
- Rebuild, reopen, report measured results and limits.
