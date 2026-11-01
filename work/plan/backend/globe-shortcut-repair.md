# Globe shortcut repair

- Evidence: physical Fn release emits key-down 179, reproduced in a native tap.
- Root cause: the mapper treats that Globe companion as another key and cancels
  the gesture; suppression covers modifier changes but misses the Globe key.
- Preserve Nemotron GPU compute, streaming tier, cleanup and enhancement defaults.
- Mapper: ignore own Fn/Globe and right Command companion key-downs.
- Tap: suppress both Globe key edges when Fn suppression is enabled.
- Tests: reproduce the mapper failure first; cover alternate bindings and complete
  double-tap sequences through the app coordinator, plus existing gesture tests.
- Performance: five-second DF3 fixture took 547 ms GPU versus 582 ms CPU;
  no supported reason to change compute or add competing GPU inference tasks.
- Verify: affected tests, lint, release package/signature; replace binary and open.
- Physical right Command and emoji suppression need testing in the rebuilt app.
- Results: reproduced failing Globe mapper test, then 16 HotkeyEngine tests,
  19 GestureKit tests, six app hands-free/warmup tests and architecture lint passed.
- Scope: no compute, quality, cleanup or model changes; no claimed ASR speedup.
- Release package and helper built; strict deep signing verification passed.
- Packaged app UUID matches the new Release executable; app PID 32511 reopened.
- Native downstream-tap probe: both Globe edges blocked, control event delivered.
  Before reopening the app, both Globe edges reached that same probe.
- Keyboard diagnostics: Input Monitoring, Accessibility and event posting granted.
- Physical Fn/right Command latching and first-start microphone behavior remain
  owner checks; no measured transcription speedup is claimed.
