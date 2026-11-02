# Solution v2 hardening
Confirmed causes: CI dependency Sendable errors; no polarity/quantifier/name guard; silent bounded-relay drops.
1. Add regression coverage for meaning carriers, then integrate a lemma-based guard preserving list formatting.
2. Make duplicate removal conservative for dictated numbers, negation and legitimate emphasis.
3. Surface relay overflow and preserve journals; no silent successful truncation.
4. Diagnose dependency compatibility before changing its pinned resolution; no compiler-check bypass.
5. Run affected tests and architecture checks; retain unresolved packaged/fixture/benchmark gates in issue.md.
The complete audio corpus, human ratings, hardware sweeps and physical gesture acceptance require real recordings/input.

Implemented: lemma-aware meaning carriers, conservative repeated-word settings, relay overflow detection blocking incomplete paste and preserving recovery journal, warm-up error interpolation correction.
Observed: initial carrier tests failed 4 assertions; targeted carrier cases then passed. SessionEngine 40 tests and TextPipeline 30 tests passed. Cleanup 44 tests passed before final added magnitude protection; final rerun passed all 44 tests and lint.
Remaining: CI dependency repair; dedicated tap thread; segment carry; fixtures/ablation/sweeps; packaged latency and physical key verification. No 9/10 or latency claim. No production binary rebuilt in this change.
Magnitude checks currently conservatively reject model conversions that replace spelled magnitude words; deterministic number formatting remains available after raw recovery.
