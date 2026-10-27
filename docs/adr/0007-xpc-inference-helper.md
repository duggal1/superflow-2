# ADR 0007: Isolate ASR and LLM runtimes in an XPC inference helper

**Status:** Partially implemented (LLM runtime moved; ASR remains in the app)

## Context

Phase 8 requires the ASR and LLM runtimes to leave the app process. A Core ML
model failure, a llama.cpp assertion, or a wedged inference call currently takes
down the menu-bar app and the session it was recording. The helper must keep the
same port contracts so the app does not learn a second API.

The helper is also the natural place for watchdogs: the app can restart a dead
helper without losing its UI, database, or journal state.

## Decision

- Add `App/InferenceHelper`, a standalone SwiftPM package with three targets:
  - `SuperflowInferenceHelperProtocol`: the `@objc` XPC protocol and a protocol
    version constant.
  - `SuperflowInferenceHelperCore`: the service object, kept free of XPC so it
    can be unit tested.
  - `SuperflowInferenceHelper`: the executable that owns `NSXPCListener`.
- Version the protocol (`InferenceHelperProtocolVersion.current`). `ping` returns
  the version so the app can refuse a mismatched helper instead of failing in an
  obscure way.
- The helper owns `LlamaCppRuntime`; `InferenceHelperService` validates and loads
  the model, then exposes token counting and completion over XPC.
- `XPCInferenceHelperRuntime` implements the runtime interface used by
  `LlamaCleaner`. A transport failure invalidates the connection, reloads the
  model through launchd, and retries the request once.
- Keep llama.cpp out of the app executable. `SuperflowLLMCore` contains the
  prompt and cleaner contract without linking the native framework; only the
  helper target depends on `SuperflowLLMLlamaCpp`.
- `make app` builds and embeds the helper at
  `Contents/XPCServices/SuperflowInferenceHelper.xpc`. The helper is required by
  default; `SUPERFLOW_REQUIRE_HELPER=0` is an explicit packaging override.
- Embed `llama.framework` inside the helper bundle and sign it before signing
  the helper and app.
- Sign the helper with the same entitlements as the app. The helper is not
  sandboxed for the same reason as the app: it will load third-party inference
  code and Metal/Core ML artifacts.
- The app still constructs `FluidAudioRecognizer` in process. Moving ASR behind
  the helper protocol is the remaining runtime-isolation work.

## Usage sketch

```swift
let connection = NSXPCConnection(serviceName: "com.superflow.app.InferenceHelper")
connection.remoteObjectInterface = NSXPCInterface(with: InferenceHelperProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxy as? InferenceHelperProtocol
proxy?.ping { version in /* compare with InferenceHelperProtocolVersion.current */ }
```

## Alternatives considered

1. Keep everything in-process and rely on crash reporting. Rejected: a runtime
   crash still loses an active recording, which the journal only partly covers.
2. Put the helper in `Packages/L1-Adapters`. Rejected: it is an executable
   composition concern, not a reusable adapter, and the layer rules reserve
   concrete process wiring for L5.
3. Define the XPC protocol in the app target. Rejected: the helper would then
   depend on the app, inverting the dependency and making independent builds
   impossible.

## Consequences and limits

The app executable no longer links `llama.framework`; the XPC helper does. The
app retries once after an XPC transport failure, and the service is packaged in
the local app bundle. ASR remains in the app. Calls that never reply do not yet
have a request deadline, and restart recovery has not been exercised by killing
the packaged helper during inference. The helper and app are ad-hoc signed for
local use; Developer ID signing and notarization remain release work.

## Evidence

- `make app`: app and helper build; the local `dist/Superflow.app` contains the
  XPC helper and its llama framework.
- `swift test --package-path App/InferenceHelper --scratch-path App/SuperflowApp/.build`:
  5 tests, 0 failures.
- `swift test --package-path Packages/L1-Adapters/LLMLlamaCpp`: 9 tests, 0 failures.
- `otool -L` confirms the app executable has no `llama.framework` dependency;
  the helper executable does.
- `codesign --verify --deep --strict dist/Superflow.app` passes for the local
  ad-hoc signature.
- `make app-smoke` covers bundle assembly, helper embedding, framework rpaths,
  signing, and required framework enforcement.
