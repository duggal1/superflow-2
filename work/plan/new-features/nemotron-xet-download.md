# Nemotron Xet Downloads

## Root cause
FluidAudio downloads Nemotron's large Xet-backed weight files as ordinary streams, so the 565 MB encoder is not reconstructed from parallel Xet chunks.

## Goal
Use Hugging Face's official Swift Xet client for large Nemotron files while preserving FluidAudio's cache structure and ordinary-download fallback.

## Non-goals
Change other model downloads, add token settings, or store credentials in the repo.

## Invariants
- Only the Nemotron multilingual profile takes the Xet prefetch path.
- Files are staged, size and SHA-256 checked, then atomically placed in FluidAudio's existing model tree.
- Cancellation propagates; other Xet failures fall back to FluidAudio's downloader.
- Tokens come from environment variables and are never logged.

## Steps
1. Add the Swift Xet dependency to the ASR adapter. Verify the package resolves.
2. Implement tree listing, large-file selection, Xet transfer, checksum validation, and atomic placement. Verify focused candidate tests.
3. Invoke prefetch only in the Nemotron branch, retaining existing FluidAudio download fallback. Verify the ASR adapter tests/build.
4. Record the issue resolution after verification.

## Files
ASRFluidAudio package manifest, Nemotron downloader, Xet downloader helper, focused ASR tests, issue.md.
