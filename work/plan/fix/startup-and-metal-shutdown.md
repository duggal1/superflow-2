# Startup and Metal shutdown
Root cause: cached audio.cpp sessions outlive app termination; cold enhancement loading delays capture consumption.
- Await cancellation and native model unload before AppKit termination, including Command-Q.
- Prepare ASR before cleanup to reduce startup GPU contention.
- Use already-prepared enhancement or raw capture; never cold-load it on the recording path.
- Make Intelligence trigger selection directly clickable through the shared segmented control.
- Verify focused app/adapter tests, build, and native load/unload process exit.

Verified: 28 session tests, five app gesture tests, native GPU load/unload, and a real AppKit quit (exit 0).
Checksum receipts avoid rehashing an unchanged model; model load measured 0.29 s, native Metal preparation 16.62 s.
Remaining: cold GPU preparation latency and live microphone/paste verification.
