# Plan: Island popup on successful paste + long-transcript latency
## Root cause (insertion, verified in code)
- TextInsertionService returns .notInserted(.pasteNotObserved) when chord posted
  (inserted=true) but AX verification timed out (inserted && !verified).
- For targets without AX text (Electron/terminals/web views) baseline is
  unusable, so verification is impossible by design, yet success is reported
  as failure. IslandBridge then shows the copy card on .finished.
SystemTextInserter already maps .inserted(verified:false) to .pasted, so fix
belongs in the service: baseline-less posted paste = landed.
Plus verifyTimeout 400ms is short for slow apps; raise so fast-paste still
returns immediately but slow-but-landed pastes verify instead of popping up.
## Performance (long transcript, hypothesis to validate)
- stop() drains capture -> recognition -> cleanup finish (2.5s cap) -> insert.
- ChunkPlanner does per-candidate token counts via XPC round trips.
Validate with SessionEngine latency metrics on a 30s fixture before changing.
## Files
- TextInsertionService.swift + Attempts: canVerify flag; service returns
  inserted when baseline-less and posted.
- InsertionTypes defaults: verifyTimeout 400 -> 1200ms.
- Tests: TextInsertionServiceTests regression (posted+no baseline => inserted).
## Verify
swift test TextInsertion, SessionEngine (incl. latency), TextPipeline; make lint.
Do not touch unrelated dirty files. Rebuild app after.
