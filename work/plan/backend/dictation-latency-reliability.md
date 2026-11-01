# Dictation latency, startup capture, and cleanup formatting
Cause: interactive cleanup recursively retries with fresh deadlines; capture consumption waits for ASR readiness; list markers are treated as content changes.
- CleanupService: remove all recursive retries; preserve intact context and safe raw fallback.
- SessionEngine lifecycle: drain capture and emit levels while ASR loads; cancel consumers on failed start.
- SessionCleanupCoordinator: record stage latency and cleanup state and diagnostic count without transcript content.
- CleanupStructure/ListPlanner/CleanGuard: recognize explicit spoken enumerations and compare list content without formatting markers.
- Preserve pinned S1 prompt, greedy decoding, model/tier/runtime, protected literals and factual-data checks.
Verification: tests skipped at user request; compile/package, review diff, verify signed binary UUIDs.
Unmeasured: real stop-to-insert distribution, recording accuracy and subjective 9/10 quality.
Model tournament, alternate ASR and training require separate measured experiments; production models stay unchanged.

Updated scope: one pass per sentence-aware, non-overlapping chunk; shared resident model and bounded worker contexts. No recursive retries, seam inference or whole-transcript revalidation. Hard token-cap, empty-output, protected-literal and factual-data checks remain; exact word equality is removed because normalization changes words. Gross shortening returns raw text. No semantic or 9/10 quality guarantee without audio evaluation.

Observed: Release app/helper packaging and strict signature verification passed; make lint passed. Tests intentionally not run. Earlier exact-word rejection expectations were updated to the normalization contract, unrun. Existing unrelated AppCoordinator+Input.swift edits remain untouched.
