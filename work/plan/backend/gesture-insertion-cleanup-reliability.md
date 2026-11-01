# Gesture, insertion and cleanup reliability

- Proven insertion fault: stale AX observations trigger a second paste and AX
  fallback after a successful event post. Accept one mutation, report verification
  separately, and preserve clipboard recovery without automatic second writes.
- Gesture investigation: serial actions accumulate behind start/stop; stale FSM
  intent can outlive failed or canceled sessions. Bound pending input and make
  Escape invalidate pending starts without allowing canceled work to paste.
- Right Command: inspect physical modifier events and meeting start failures;
  fix the demonstrated boundary, not the pure timing logic by assumption.
- Cleanup: preserve the pinned S1-mini prompt and trained prose/lists controls.
  Add deterministic structure after cleanup, including model-unavailable fallback;
  reassert numbers/lexicon, retain protected spans and existing bounded workers.
- Inventory existing duplicate removal, quantities, chunking, VAD and model cache;
  add missing behavior only, with quality/content and cancellation regressions.
- Verify affected tests before/after, real local model availability, long synthetic
  assembly, lint and Release app/helper. Replace/open the signed build.
- Never suppress whispering with stronger VAD gates or promise unmeasured speed.
- Results: stale-AX duplicate regression reproduced; insertion 88, hotkey 18,
  app gesture/hands-free 7, session 40, meeting 17, cleanup 41, pipeline 29,
  disfluency 30 and S1-mini 19 tests passed across focused runs.
- Live S1-mini: pinned checksum verified, GPU examples and cancellation passed;
  exact prompt/thinking-off template retained. Silero and enhancement installed.
- Release app/helper rebuilt and signed; new app opened. Native Globe probe
  blocked both edges while delivering its control. Synthesized right Command
  double-tap reached meetingLatched; Escape followed. Physical key check remains.
- No 30-minute–10-hour audio or whisper corpus was supplied: those quality and
  performance claims remain unmeasured. No GPU/model/tier defaults changed.
- Follow-up native probe: a synthetic right-Command double-tap reached the
  meeting gesture, and a process sample showed the meeting microphone running
  through DeepFilterNet and ASR. Startup had not completed when Escape was
  sent after seven seconds; cancellation left a failed session record. Full
  meeting readiness and the physical shortcut remain UNTESTED.
