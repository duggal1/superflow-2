# Model cache repair

## Cache locations

- Streaming ASR: `~/Library/Application Support/Superflow/Models/FluidAudio/`. FluidAudio owns these model files and their layout.
- S1-mini GGUF: `~/Library/Application Support/Superflow/Models/s1-mini-q4-k-m/` (directory and filename follow `model-manifest.json`). `ModelStore` verifies the manifest's byte count and SHA-256 and writes a `.verified` sidecar.
- Diarization: not integrated in the current app composition. Meetings currently use the single-remote-speaker fallback.

## Re-download a missing or invalid S1-mini file

1. Open Settings → Models and use the download action. Keep Superflow open while the progress indicator runs.
2. The downloader writes to a temporary file, checks the manifest size and SHA-256, then atomically moves the verified file into place.
3. If the download repeatedly fails, quit Superflow. Move the model's cache directory to a backup location; do not delete it until a verified replacement is available.
4. Reopen Settings → Models and download again. The app should report the installed model as available after verification.

## Repair streaming ASR

1. Confirm there is enough free disk space and a working network connection. Do not start a recording while preparing a model.
2. Quit Superflow and move `Models/FluidAudio` to a backup location if the cache is suspected to be incomplete.
3. Relaunch and complete the model preparation action in onboarding or Settings. FluidAudio will rebuild/download its required model bundle.
4. Confirm the model is available in Settings before testing a recording.

Never copy an artifact from an untrusted source into either cache. Do not use the LLM manifest to repair ASR: ASR is managed by the FluidAudio adapter, while `ModelStore`'s checked-in manifest describes S1-mini.
