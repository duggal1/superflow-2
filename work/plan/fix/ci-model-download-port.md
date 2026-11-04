# Plan: Repair CI layer dependency

## Root cause
`ASRSherpaOnnx` depends on `ModelStore` for `ModelDownloading`, an adapter-level contract that belongs in L0 Ports.

## Goal
Remove the L1-to-L1 dependency without weakening dependency checks or changing download behavior.

## Changes
- Move `ModelDownloading` to `SuperflowPorts` and keep `ModelStore` as its concrete implementation consumer.
- Inject the downloader into `SherpaOnnxModelStore` and its recognizer composition.
- Remove the `ModelStore` package dependency and replace test imports with `SuperflowPorts`.
- Use sherpa-onnx's static product so SwiftPM test hosts do not need an unbundled runtime dylib.
- Fix the seven existing `lint-forbidden` blockers exposed once `deps-check` passes.
- Build the pinned audio.cpp native library before Swift tests and app linking.
- Make the native build script check out its declared audio.cpp commit before compiling.
- Have audio.cpp integration tests install checksum-verified model assets through the production model API.
- Record the confirmed CI issue and verification in `issue.md`.

## Verification
- Run `tools/check-deps` and affected package tests.
- Run `make verify`, review the diff, then push a branch and open a PR for GitHub checks.
