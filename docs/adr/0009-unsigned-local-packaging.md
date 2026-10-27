# ADR 0009: Assemble an ad-hoc signed local app bundle

**Status:** Accepted

## Context

Developer ID signing and notarization need an Apple account and a stable
certificate. Neither is available in this environment, but the app still has to
be assembled, launched, and inspected to prove that packaging works. The bundle
also has to carry the microphone entitlement and embed the llama framework and
the XPC helper, or the built product is not representative.

The previous `tools/package-app` assumed a full successful app build, hard-coded
the llama framework, had no entitlement or helper handling, and could not be
tested without the whole dependency graph.

## Decision

- `tools/package-app` assembles `dist/Superflow.app` from SwiftPM products:
  executable, `*.bundle` resources, optional `llama.framework`, and optional
  `Contents/XPCServices/SuperflowInferenceHelper.xpc`.
- Sign everything ad-hoc (`-` by default) with
  `App/Resources/Superflow.entitlements`, using the hardened runtime option.
  `SUPERFLOW_SIGN_IDENTITY` selects a real identity later without changing the
  script.
- The entitlements keep the app non-sandboxed (event taps and synthetic paste
  require it), grant audio input, and disable library validation so an ad-hoc
  app can load separately signed inference frameworks. A Developer ID build may
  revisit the last item.
- Missing optional pieces are warnings by default so a local bundle can be built
  before every model artifact exists. `SUPERFLOW_REQUIRE_MODELS=1` and
  `SUPERFLOW_REQUIRE_HELPER=1` make them errors for release-style checks.
- Provide overrides (`SUPERFLOW_APP_BINARY`, `SUPERFLOW_BIN_DIR`,
  `SUPERFLOW_HELPER_BINARY`, `SUPERFLOW_LLAMA_FRAMEWORK`,
  `SUPERFLOW_APP_OUTPUT`) and `--skip-build`/`--smoke`, so the assembler can run
  against a prepared binary without invoking SwiftPM.
- Add `tools/test-package-app` (wired as `make app-smoke`). It compiles tiny
  Mach-O stubs and exercises: minimal bundle, full bundle with helper and
  framework, missing executable, required-but-missing framework, and `--help`.
- Keep smoke checks in the assembler itself: the executable exists, the
  `CFBundleExecutable` and identifier match, the helper is a valid `XPC!`
  bundle, `codesign --verify --deep --strict` passes, and the signed app carries
  `com.apple.security.device.audio-input`.

## Consequences and limits

- Ad-hoc signatures have no stable identity, so macOS TCC grants can reset when
  the binary is rebuilt. Users may be re-prompted for Microphone, Accessibility,
  and Input Monitoring. This is expected for local builds and is why the plan
  requires a stable signing identity from day one for real distribution.
- The bundle is not notarized and is not distributable. Gatekeeper will reject
  it on another Mac; `spctl` assessment is not part of the smoke test.
- `--skip-build` trusts the supplied binary. It still validates structure and
  signatures, but it cannot prove the binary matches the current sources.
- The real `llama.framework` is embedded and signed, but model files are not.
  First-run model download remains a separate onboarding concern.

## Evidence

- `make app` produced a 64 MB bundle containing `llama.framework`, seven resource
  bundles, and the XPC service; `codesign --verify --deep --strict` passed.
- The packaged executable stayed alive for 6 seconds both when launched directly
  and through LaunchServices (`open dist/Superflow.app`).
- `make app-smoke` passes all five assembler scenarios.
- The app build in this environment used `SUPERFLOW_HARPER_FFI=0` because the
  real Harper xcframework currently fails to copy its umbrella header. That is a
  GrammarHarper packaging defect, not a packager defect; see the remaining-gaps
  report.
