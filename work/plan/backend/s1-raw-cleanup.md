# S1-mini cleanup path
- Root cause: deterministic stages change ASR before S1-mini; the exact-word guard
  rejects valid normalizations, causing retries and raw fallback. Harper can run afterward.
- Send raw input to S1-mini first, preserve deterministic stages after it, and
  remove Harper from the app and pipeline execution.
- Let the cleaner handle each bounded chunk once; keep explicit protected-data,
  token-cap, empty-output and gross truncation safeguards and safe fallback.
- Verify pipeline order, raw model input, normalization, protected data and
  formatting; run targeted packages and live S1-mini, then build the app.
- Measure stop-to-insert separately; long-audio/hardware claims require real runs.
- Verified: 42 cleanup, 30 pipeline, 40 session and 19 S1-mini/runtime tests passed.
- Reproduced the documented self-correction being rejected before the guard fix.
  Protected-data, missing-content, duplicate-output and truncation regressions pass.
- Removed pre-model list splitting and duplicate formatting passes. Harper is
  removed from app dependencies/wiring and never scheduled by the pipeline.
- Reference: https://huggingface.co/superwhisper/s1-mini (exact pinned prompt kept).
  FluidAudio v0.17.7 NemotronMultilingual guide reviewed; model/runtime unchanged.
- Stop-to-insert 500 ms–1 s and long-audio/whisper quality remain UNTESTED.
