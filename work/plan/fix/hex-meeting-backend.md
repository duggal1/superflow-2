# Hex meeting backend adoption plan
Date: 2026-11-03. Scope: meeting capture, transcription reliability and durable completion; planning only.
Reference: local Hex commit fbb41e4385b792c9592e01321667e6c3466d24c0; no claim that this is upstream HEAD.
## Decision
Port selected algorithms/contracts into Swift; do not embed Hex's Rust app or replace the backend wholesale.
Preserve MeetingIntelligence, Reflection, prompts, OCR, ASR/diarization model choices, existing UI and privacy settings.
Our backend already has dual lanes, journal replay, speaker labels, shared initial offsets, bounded resident turns and persistent echo-drop markers.
## Evidence and priority
| Priority | Hex implementation | Superflow gap or risk | Decision |
|---|---|---|---|
| P0 | `hex/src/meeting.rs`: `write_tracks`, atomic transcript publication, `final.pending`, `finish_pending` | `MeetingTurns.persist`, `resolve`, and `MeetingEngine.stop` suppress repository errors; stop can mark complete and delete journals after failed writes. Existing RecoveryEngine already replays journals. | Adopt successful-publication-before-complete invariant; extend existing recovery, not a second manifest system. |
| P1 | `hex/src/meeting_capture.rs`: `supervise`, bounded retry, 3-second stall detection, independent sources | Microphone already follows routes and detects stalls; CoreAudioTap already restarts on device events. SystemAudioCapture selects fallback only at startup; engine failure handler marks loss without reconnecting. | Add missing supervision around system failure/stall and failed restarts; preserve working lane. |
| P1 | `hex/src/meeting.rs`: `missing_samples`, `TrackGap`, packet positions | Engine maps a one-time startup offset; reopened-source gaps need explicit accounting across live, persisted and replay clocks. | Reuse monotonic/sample-clock types; record exact missing intervals, never silently compress time. |
| P2 | `hex/src/meeting_echo.rs`: `EchoEnvelope`, lag/coupling/locality classification | Our `MeetingTurns.isDuplicate` uses text similarity and overlap, which cannot distinguish real simultaneous repetition from speaker bleed. | Port signal evidence conservatively; unknown/local microphone speech must survive. |
| P2 | `hex/src/meeting_transcript.rs`: `RollingFeed`, bounded nonblocking feed, incomplete-track rebuild | Our audio loop awaits journal, enhancement and recognizer work; committed turns spawn one cleanup Task each without a pending-task cap. | Bound recognition/cleanup scheduling; recover skipped derived work from journals without dropping canonical audio. |
## Ordered implementation
1. Durability first: modify `MeetingTurns.swift`, `MeetingEngine.swift`, `MeetingDocumentProjection.swift` and focused MeetingEngine tests; extend RecoveryEngine only where necessary. On write/read/finalize failure retain journals and a recoverable state, emit a metadata-only notice, never publish successful completion. Preserve existing method contracts unless a typed result is necessary.
2. Independent source recovery: add focused `MeetingSourceSupervisor.swift` in MeetingEngine; integrate through `MeetingCapture.swift`, `SystemAudioCapture.swift` and AppEnvironment injection only if needed. Retry failed system opens with 500 ms–5 s backoff; stop retrying on revoked permission or cancellation. Use a fake clock and current adapter restart behavior rather than duplicate mic logic.
3. Timeline continuity: new focused meeting timeline helper plus source gap records using existing storage contracts where possible. Keep recognizer-local coordinates separate from shared persisted coordinates. Preserve silence/gap evidence during replay; changing schema requires a separately reviewed migration.
4. Echo classification: new `MeetingEchoEnvelope.swift` and tests; consume bounded 20 ms energy summaries outside audio callbacks, integrate with MeetingCapture/MeetingTurns. Delay destructive suppression until enough aligned evidence exists; persist original audio and raw transcripts. Replace automatic text-only dropping only after replay tests prove safe behavior.
5. Bounded derived work: add a focused meeting work scheduler and tests; integrate persist/finishCapture. Durable audio must remain independent of slow ASR/cleanup; overflow schedules replay rather than allocating unbounded Tasks. Stop drains or records pending work, and retries do not duplicate segments.
## Acceptance tests, written before each implementation
- Durability: injected append/update/read/finalize failure never deletes journals or reports complete; restart recovery twice produces one canonical result.
- Recovery: system stall, output-device change and transient reopen failure preserve microphone capture; permission revocation stops retries; Stop prevents late restart callbacks.
- Timeline: delayed start, two-second dropout, rate change and reopened source maintain exact expected sample positions; live/recovered turns remain aligned.
- Echo: delayed/attenuated bleed suppressed; headphones, local-only speech, simultaneous speakers, short local interjections and uncertain evidence preserved. Port Hex's synthetic cases and add consented real two-lane recordings before enabling suppression by default.
- Backpressure: slow recognizer/cleaner under a simulated three-hour meeting keeps pending counts bounded; every durable sample interval is transcribed or explicitly pending/gapped; repeated finalization remains idempotent.
- Per step run affected package tests (`swift test --package-path Packages/L2-Engines/MeetingEngine --jobs 2` and changed adapters/recovery packages); run architecture checks after stabilization and `make verify` at release, then signed native two-source smoke test.
## Excluded and reuse constraints
No summaries, chapters, MCP, cross-meeting search or calendar/auto-recording in this change. Hex implements those, but they expand scope or overlap intelligence; detection would require a separate opt-in product decision.
No claim that Hex's thresholds are optimal for Nemotron. Preserve existing streaming recognition and diarization; do not import its Parakeet-specific buffering, cloud routes, full-track memory retention or product UI.
Local `hex/LICENSE` is MIT, copyright Christopher Langton, 2026. Preserve its notice with any copied substantial code; existing Hex attribution must be checked before landing ports. Exact source references above are local paths, not unverified vendor feature claims.
## Validation record
See `hex-meeting-validation.md` beside this plan for commands, results and explicit limits. Implementation remains unstarted.
