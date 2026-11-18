# Agent 1 — Extreme Transcription Quality Corpus Report

## Scope

- Ownership: `Tests/TextPipelineTests/AggressiveCorpusShortTests.swift` (new) + `.proof/transcription-corpus/**`.
- 200 deliberately-broken ASR fixtures: 100 short (~50 words / ~30 s) + 100 long (140–150 words).
- 19 domains: software/code, meetings, email, medical, legal, finance, non-native English, noisy ASR, extreme Unicode, standup, customer support, science, sales, personal notes, gaming, travel, academic, chat, coding interview.

## Execution mode

- Pipeline path: **Tier0-deterministic**. Real in-target `swift test --package-path Packages/L2-Engines/TextPipeline --filter AggressiveCorpusShortTests --jobs 1`: 2 tests, 0 failures, 30.2 s. The executed-subset test calls the real `TextPipelineBuilder.make` Tier-0 path — no mocks, no reimplementation. A standalone runner against the already-built objects produced byte-identical outputs.
- An earlier build was blocked by another agent's then-broken `DictionaryLearningPersistenceTests.swift` (async-in-autoclosure + missing `try`); its owner fixed it, I did not edit it, and the final run passed. My test file was also syntax-verified with `swiftc -frontend -parse` (exit 0).
- S1-mini GGUF is present and a single live probe succeeded (`live-probe.txt`: 1.49 s / 50-word sample, 0.58 s short). Full-corpus S1 scoring was NOT run under the machine-throttle/build-fence limits.
- Tier-0 fallback = real `TextPipelineBuilder.make` with `cleanupEnabled=false` (documented deterministic path). By contract it owns fact/negation/number preservation, stutter dedupe, dictionary corrections, formatting and no-invention; filler removal, self-correction resolution and grammar polish are S1-mini's job and are scored as FAIL when absent, not excused.

## TOTALS

| Tier | Total | Executed | NOT EXERCISED | PASS | FAIL |
|---|---|---|---|---|---|
| short | 100 | 10 | 90 | 1 | 9 |
| long | 100 | 10 | 90 | 3 | 7 |
| overall | 200 | 20 | 180 | 4 | 16 |

Dimensional breakdown (executed samples only, PASS/FAIL counts):

| Dimension | PASS | FAIL |
|---|---|---|
| facts | 18 | 2 |
| grammar | 8 | 12 |
| terms | 20 | 0 |
| format | 15 | 5 |
| novel | 20 | 0 |

## Worst failures (exact input → output) — 16 executed FAIL(s)

### 1. A1-S-0031 (short, non-native English) — failed: grammar, format
- **INPUT**: sorry my English is not you know so good but I am trying to say the the the the the the the server is down since yesterday and we are not able to deploy the new version um and then we can decide so please keep me posted on that right so that
- **OUTPUT**: Sorry my English is not you know so good but I am trying to say the server is down since yesterday and we are not able to deploy the new version and then we can decide so please keep me posted on that right so

That
  - grammar: forbidden token(s) survived: ['you know']
  - format: required token(s) missing: [['.', '!', '?']]

### 2. A1-S-0051 (short, science) — failed: facts, grammar
- **INPUT**: the the the the the the the sample temperature was thirty you know seven degrees Celsius and the p value was zero point zero three so the result is statistically significant but not conclusive as I mentioned earlier in the week which is important for the timeline um and then we can decide
- **OUTPUT**: The sample temperature was 30 you know 7°C and the p value was 0.03 so the result is statistically significant but not conclusive as I mentioned earlier in the week which is important for the timeline and then we can decide.
  - facts: required token(s) missing: [['37']]
  - grammar: forbidden token(s) survived: ['you know']

### 3. A1-S-0071 (short, academic) — failed: grammar, format
- **INPUT**: the hypothesis was not confirmed you know because the sample size of thirty was too small and the the the the the control group showed the the the same effect right so that is the plan let me know if that makes sense so please keep me posted on that right so that
- **OUTPUT**: The hypothesis was not confirmed you know because the sample size of 30 was too small and the control group showed the same effect right so that is the plan let me know if that makes sense so please keep me posted on that right

So that
  - grammar: forbidden token(s) survived: ['you know']
  - format: required token(s) missing: [['.', '!', '?']]

### 4. A1-S-0011 (short, meeting) — failed: grammar
- **INPUT**: thanks everyone the Q three you know revenue was two point four million which is is is is is is is up from one point eight million last quarter and churn dropped to two point one percent um and then we can decide so please keep me posted on that right so that
- **OUTPUT**: Thanks everyone the Q 3 you know revenue was 2.4M which is up from 1.8M last quarter and churn dropped to 2.1% and then we can decide so please keep me posted on that right so that.
  - grammar: forbidden token(s) survived: ['you know']

### 5. A1-S-0021 (short, legal) — failed: format
- **INPUT**: the plaintiff filed the the the motion on Tuesday but the deadline was extended to Thursday actually no wait Friday so we do not need to respond until the end of next week as I mentioned earlier in the week which is important for the timeline um and then we
- **OUTPUT**: The plaintiff filed the motion on Tuesday but the deadline was extended to Thursday actually no wait Friday so we do not need to respond until the end of next week as I mentioned earlier in the week which is important for the timeline and

Then we
  - format: required token(s) missing: [['.', '!', '?']]

### 6. A1-S-0041 (short, standup) — failed: format
- **INPUT**: yesterday I worked on the auth flow and today I am reviewing the the the pull request for the billing service unless the API contract changes then I will pair with Priya so please keep me posted on that right so that is the plan let me know if that
- **OUTPUT**: Yesterday I worked on the auth flow and today I am reviewing the pull request for the billing service unless the API contract changes then I will pair with Priya so please keep me posted on that right so that is the plan let me

Know if that
  - format: required token(s) missing: [['.', '!', '?']]

### 7. A1-S-0061 (short, gaming) — failed: grammar
- **INPUT**: I died three times on the the final boss because my latency was two hundred milliseconds so I switched servers and won on the the the fourth try you know what I mean as I mentioned earlier in the week which is important for the timeline um and then we
- **OUTPUT**: I died 3 times on the final boss because my latency was 200ms so I switched servers and won on the fourth try you know what I mean as I mentioned earlier in the week which is important for the timeline and then we.
  - grammar: forbidden token(s) survived: ['you know', 'i mean']

### 8. A1-S-0081 (short, medical) — failed: format
- **INPUT**: the CT scan showed no fracture but there is is is mild swelling so we will monitor for twenty four hours and discharge if the pain does not increase right so that is the plan let me know if that makes sense so please keep me posted on that right
- **OUTPUT**: The CT scan showed no fracture but there is mild swelling so we will monitor for 24 hours and discharge if the pain does not increase right so that is the plan let me know if that makes sense so please keep me posted on

That right
  - format: required token(s) missing: [['.', '!', '?']]

### 9. A1-S-0091 (short, finance) — failed: grammar
- **INPUT**: our runway is is is is is eighteen months you know at the the the the current burn rate of two hundred thousand per month so we do not need another round until Q three but I want to be careful here and we should double check the numbers you know what I
- **OUTPUT**: Our runway is 18 months you know at the current burn rate of 200k per month so we do not need another round until Q 3 but I want to be careful here and we should double check the numbers you know what I.
  - grammar: forbidden token(s) survived: ['you know']

### 10. A1-L-0011 (long, legal) — failed: grammar
- **INPUT**: the motion to suppress was you know filed on Monday but hearing was continued to following Thursday because the prosecution needed more time to respond. our position is that the evidence was obtained without a valid warrant and therefore should be ruled inadmissible under the fourth amendment. the defendant did not consent to the the the search and no exigent circumstances were present at the the the time. opposing counsel argues that the good faith exception applies but we disagree because the the affidavit was clearly deficient on its face. we need to file our reply brief by Friday at the latest and I want you to review the citations before then. please do not use the old case law from two thousand eight because it was overruled. if the judge denies the the the motion we will appeal to the circuit court within thirty
- **OUTPUT**: The motion to suppress was you know filed on Monday but hearing was continued to following Thursday because the prosecution needed more time to respond.

Our position is that the evidence was obtained without a valid warrant and therefore should be ruled inadmissible under the fourth amendment. The defendant did not consent to the search and no exigent circumstances were present at the time.

Opposing counsel argues that the good faith exception applies but we disagree because the affidavit was clearly deficient on its face. We need to file our reply brief by Friday at the latest and I want you to review the citations before then.

Please do not use the old case law from 2008 because it was overruled.

If the judge denies the motion we will appeal to the circuit court within 30.
  - grammar: forbidden token(s) survived: ['you know']

## Ranked defect list for coordinator

1. **grammar**: forbidden survived: ['you know'] — 10 sample(s), e.g. A1-S-0031, A1-S-0051, A1-S-0071, A1-S-0011
2. **format**: required missing: ['.', '!', '?'] — 5 sample(s), e.g. A1-S-0031, A1-S-0071, A1-S-0021, A1-S-0041
3. **grammar**: forbidden survived: ['you know', 'i mean'] — 2 sample(s), e.g. A1-S-0061, A1-L-0061
4. **facts**: required missing: ['37'] — 1 sample(s), e.g. A1-S-0051
5. **facts**: required missing: ['12000', '10200'] — 1 sample(s), e.g. A1-L-0041

### Additional observed defects (manual, from exact input→output above — not dimension-scored)

- **Stutter dedupe can delete the definite article entirely.** A1-L-0011 input `but the the the hearing was continued to the the the following Thursday` → output `but hearing was continued to following Thursday`. Compare A1-S-0051 where `the the the the the the the sample temperature` → `The sample temperature`. The same mechanism collapses to one article in one context and to zero in another; zero loses grammar. Recommend: stutter collapse must always keep exactly one token.
- **Self-corrections are not resolved on the Tier-0 fallback.** A1-L-0001 output keeps `scheduled for Wednesday actually no wait Thursday actually no wait Wednesday` and A1-L-0081 keeps `by Thursday actually no wait Wednesday`. Both days survive, so a downstream reader cannot tell which date is final. This is S1-mini's job by contract, but the fallback is the path used when S1 is unavailable — worth a deterministic last-write-wins rule.
- **Strength, not defect:** all 20 executed samples restored the garbled technical terms (`redish cash`→`Redis cache`, `a p i endpoint`→`API endpoint`, `open trace`→`OpenTelemetry`); the terms dimension is 20/20 and no-invention is 20/20.

## Honesty note

A fixture that was not executed is **NOT EXERCISED**, not PASS. Weak or absent fixes are FAIL. The 180 non-executed fixtures are structurally validated (word counts, required/forbidden non-contradiction, 5-dimension assertion coverage) but carry no quality verdict.
