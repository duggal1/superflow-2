# Hex meeting comparison validation

Inspected local Hex snapshot `fbb41e4385b792c9592e01321667e6c3466d24c0`; this is a source comparison, not proof of current upstream parity. Relevant implementation anchors and ordered tasks are in hex-meeting-backend.md.

- `swift test --package-path Packages/L2-Engines/MeetingEngine --jobs 2`: 17 XCTest tests passed, zero failures. This establishes the existing baseline, not the planned improvements.
- Isolated `hex/src/meeting_echo.rs` in a temporary Rust test harness supplying only the two-value MeetingSource enum. Removed serde import, serialization derives and serde enum attribute to avoid building the entire Hex app; DSP logic and seven upstream tests were unchanged. `rustc --edition=2024 --test /tmp/hex-echo-audit.rs -o /tmp/hex-echo-audit` followed by `/tmp/hex-echo-audit --quiet`: seven passed. One unused-method warning. Cases cover delayed bleed, double-talk, remote silence, muffled/reverberant echo, short local interjections, headphones and discontinuous packets.
- The full Hex application, capture adapters and physical devices were not executed. Synthetic tests do not establish real-room echo accuracy, latency, CPU or memory improvements in Superflow.
- Superflow microphone already has route/stall handling, and CoreAudioTap has event-triggered restarts. The proposed supervisor adds persistent failed-restart/fallback recovery; it must not replace or duplicate functioning route logic.
- Direct source finding: MeetingTurns suppresses append/update failures; MeetingDocumentProjection substitutes empty arrays after read failures; MeetingEngine.stop suppresses finalize failure and then deletes journals when keepJournals is false. An injected-storage-failure regression is required before changing behavior. This risk is recorded as unresolved, not a reproduced user incident.
- Existing recovery already scans interrupted sessions and replays journals. Reuse it; Hex's separate final.pending file is a concept reference, not a recommendation to introduce a duplicate source of truth.
- No production code, meeting intelligence behavior, UI or model configuration changed during this planning task.
