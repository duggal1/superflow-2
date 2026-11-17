# Extreme transcription quality — final results

- Baseline quality harness (real S1-mini, 15 garbled fixtures): **15/15 PASS**
- Extreme quality harness (real S1-mini, 8 broken fixtures): **8/8 PASS**
- Deterministic Tier-0 extreme gate: **11/11 PASS**
- TextCleanup 112, TextPipeline 97, Disfluency 30, CodeAware 21, Numbers 40, LineFormat 19, App 98 — all green
- `tools/lint-forbidden`: clean. Release build: green.

## Root causes fixed

1. MeaningCarriers guard miscounted negators in self-corrections ("not a 500 wait no 429") and false-start doubles ("don't not"), causing valid S1-mini output to be rejected and fall back to raw text. Now scoped to revision cues; real negation drops still rejected.
2. RepeatedPathSegment repair collapses model path slips ("backend/backend") before the guard.
3. CleanGuard path comparison now accepts a model-completed spoken path ("lib slash backend" -> "lib/backend/...") while still rejecting invented separators in plain prose.
4. TruncationDetector accepts unit expansions ("ms" -> "milliseconds") and RepeatedPathSegment repairs, so valid cleanup is not discarded as truncated.
5. CodeAware joins spoken "dash" separators into filename stems.

## Verified output (excerpt)

Garbled tech: "Okay so the JWT token it's expired you know and the API is is returning a four zero three not a five hundred wait no four two nine..."
-> "Okay, so the JWT token is expired, and the API is returning a 429 because the rate limiter is kicking in."

Professional meeting: "the the Q three numbers revenue was uh two point four million dollars ... churn rate dropped to two point one percent ... you know which we shipped in in July"
-> "Thanks, everyone. So let's start with the Q3 numbers: revenue was $2.4 million ... the churn rate dropped to 2.1% from 3.4%... which we shipped in July."
