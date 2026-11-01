# Backend runtime and input: results

## License and language

Hex is MIT (Christopher Langton, 2026); the notice ships as
`App/SuperflowApp/Sources/SuperflowAppCore/Resources/ThirdPartyNotices/Hex-LICENSE.txt`
and is loaded by `AppEnvironment.loadThirdPartyNotices`. Behaviour was reimplemented
from reading Hex; no Hex UI, assets, branding, or strings were copied. Hex's meeting
backend is Rust plus Swift, so anything ported is translated to Swift.

## Model load (workstream 1)

Measured with `tools/profile-coreml-load.swift` on the installed 2240 ms tier; raw
numbers in `docs/perf/baseline-2026-11-01.json`.

| Stage | Fresh process |
| --- | --- |
| encoder load, GPU warm cache | 0.78-1.59 s |
| encoder load, GPU first ever | 4.32 s |
| encoder load, CPU warm cache | 6 ms |
| encoder load, CPU first ever | 6.79 s |
| encoder load, ANE | 139-370 s |
| decoder / joint / decoder_joint | < 4 ms each |

Root cause: the resident process is the only way to avoid rebuilding the GPU encoder
graph; there is no cross-process instance cache. Fixes: silent background prewarm,
pool reuse with no unload, launch-at-login toggle (already existed), automatic and
sudden termination disabled, ASR loads before cleanup prewarm, and the stop path
pastes before archive/HISTORY finalize.

Not measured: packaged-app process-start to prewarm return. The CLI probe does not
share Core ML caches with the app bundle, so the 20-30 s report is not yet reproduced
or refuted end to end. UNTESTED.

## Text insertion (workstream 2)

Root cause: container elements (AXApplication, tables, lists) were classified as
non-editable, so the paste chord was never posted; the chord was also posted at the
HID tap instead of the session tap. Fixed with preparation at record start, 4/6/4 ms
chord timing, modifier-release wait, clipboard snapshot restore, Secure Input
detection, and a permission prompt with pending-text retry. 88 TextInsertion tests
pass. A real paste into one native and one Chromium field is UNTESTED.

## Hotkeys (workstream 3)

Root cause: fn arrives as a modifier flag, not a key. Mapper uses `.maskSecondaryFn`,
double-tap decides from the release timestamp, right-Command is tracked by device
flags, and the Globe "Press fn key to" conflict is enforced to Do Nothing and
swallowed at the tap. 15 mapper and 19 gesture tests pass. Physical fn, double-tap,
and right-Command on hardware are UNTESTED.

## Meetings (workstream 4)

Inventory only; no port was requested or approved.

| Feature | Hex files | Status | Superflow today | Effort | Recommendation |
| --- | --- | --- | --- | --- | --- |
| Call auto-detection | `meeting_detection.rs`, `meeting_watcher.rs` | works, tested | none | M | Port: local-only, matches ADR 0015 |
| Calendar reminders | `calendar.swift` | works | none | M | Port later: needs Calendar permission |
| Live chapters | `meeting_chapters.rs` | works, cloud/Apple FM | none | L | Defer: reimplement locally with evaluation |
| Titles/summaries | `meeting_generator.rs` | cloud-dependent | none | L | Skip: violates no-cloud rule |
| System audio capture | `capture-core/system_audio.rs` | works | process tap + SCK | - | Skip: existing is better |
| Diarization | `meeting.rs` | works | FluidAudio | - | Skip: exists |
| Export | - | works | MeetingExport | - | Skip: exists |
| Replay harness | `meeting_live_replay_tests.rs` | works | none | S | Optional: borrow the test approach |
| Browser media pause | `browser_media.rs` | works | none | M | Skip: out of scope |

## Gates

`swift build App/SuperflowApp`, TextInsertion, HotkeyEngine, GestureKit, SessionEngine,
ASRFluidAudio and App tests are green. `make lint` was red because the stop-path
commit pushed `SessionEngine+Lifecycle.swift` to 411 lines; the pending-insertion
retry now lives in its own file. `make verify` is the release gate.

Remaining UNTESTED: packaged-app cold launch time, real AX paste, physical fn and
right-Command, and any compute-policy change (needs WER on >=200 utterances).

## Latest test-build continuation

Bounded speculative cleanup is implemented behind `SUPERFLOW_SPECULATIVE_CLEANUP=1`
(default off). It processes a completed-sentence partial through the unchanged
whole-segment pipeline, reusing the result only for identical final input, session,
pipeline revision and compatible context. Revised text falls back to normal cleanup.
One inference task remains the limit even during cancellation. No sentence fragments
are joined to manufacture a new transcript. GPU-contention and real-model quality
gates remain pending, so this is opt-in rather than the product default.

Verification: 39 SessionEngine tests pass, including cancellation, stale-input
rejection and 100 synthetic equivalence fixtures; `make lint` passes. Synthetic
equivalence does not establish real-model WER or stop-to-paste performance.
Call detection and calendar reminders remain outstanding. The latest owner request
prioritizes a fresh release app for hands-on testing before further implementation.
