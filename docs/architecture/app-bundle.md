# App bundle and XPC boundary

The packaged app is assembled by `tools/package-app`; `make app` runs it and
`make app-smoke` exercises the assembler against stub binaries.

## Layout

```
Superflow.app/
  Contents/
    Info.plist                         # App/Resources/Info.plist
    MacOS/SuperflowApp                 # SwiftPM executable
    Resources/*.bundle                 # SwiftPM resource bundles
    Frameworks/llama.framework         # when the LLM artifact is present
    XPCServices/SuperflowInferenceHelper.xpc/
      Contents/
        Info.plist                     # App/Resources/InferenceHelper-Info.plist
        MacOS/SuperflowInferenceHelper
    _CodeSignature/
```

`Contents/Info.plist` and the executable name must agree; the packager reads
`CFBundleExecutable` instead of hard-coding a second copy of the name.

## Inference helper

`App/InferenceHelper` is an independent package:

| Target | Responsibility |
| --- | --- |
| `SuperflowInferenceHelperProtocol` | `@objc` XPC protocol and version |
| `SuperflowInferenceHelperCore` | `InferenceHelperService`, testable without XPC |
| `SuperflowInferenceHelper` | `NSXPCListener.service()` executable |

The app does **not** connect to the helper yet. The concrete ASR and LLM
adapters still run in-process; see ADR 0007 for the remaining Phase 8 work. The
helper is embedded when it has been built and is omitted otherwise, so app-only
builds stay possible.

## Signing and entitlements

Local builds are ad-hoc signed (`-`) with the hardened runtime and
`App/Resources/Superflow.entitlements`:

- `com.apple.security.app-sandbox` = `false` — event taps and synthetic paste
  are unavailable to sandboxed apps.
- `com.apple.security.device.audio-input` = `true` — microphone access.
- `com.apple.security.cs.disable-library-validation` = `true` — load separately
  signed inference frameworks from an ad-hoc app.

`SUPERFLOW_SIGN_IDENTITY` selects a real identity for a Developer ID build. TCC
grants are tied to the signing identity, so rebuilding an ad-hoc bundle can
re-prompt for Microphone, Accessibility, and Input Monitoring.

## Commands

```bash
make app            # build App/SuperflowApp and assemble dist/Superflow.app
make app-smoke      # test the assembler with Mach-O stubs
tools/package-app --help
```

Useful overrides: `SUPERFLOW_APP_OUTPUT`, `SUPERFLOW_APP_BINARY`,
`SUPERFLOW_BIN_DIR`, `SUPERFLOW_HELPER_BINARY`, `SUPERFLOW_LLAMA_FRAMEWORK`,
`SUPERFLOW_REQUIRE_MODELS=1`, `SUPERFLOW_REQUIRE_HELPER=1`,
`SUPERFLOW_SIGN_IDENTITY`, and `CONFIGURATION`.

## Known limits

- The bundle is not notarized and is not distributable.
- The packager does not download models; onboarding owns that.
- Building the real Harper backend currently fails because the generated
  xcframework's copied `include/` directory lacks `harper_ffi.h`. Until the
  GrammarHarper owner fixes that, build with `SUPERFLOW_HARPER_FFI=0` to use the
  package's supported C stub.
