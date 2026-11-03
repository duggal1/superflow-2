# Startup and Metal shutdown
Root cause: cached audio.cpp sessions outlive app termination; cold enhancement loading delays capture consumption.
- Await cancellation and native model unload before AppKit termination, including Command-Q.
- Prepare ASR before cleanup to reduce startup GPU contention.
- Use already-prepared enhancement or raw capture; never cold-load it on the recording path.
- Make Intelligence trigger selection directly clickable through the shared segmented control.
- Verify focused app/adapter tests, build, and native load/unload process exit.
