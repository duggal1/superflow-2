# Review of solution v2 against 4914d8e

Verdict: partial, not release-ready or demonstrated 9/10 quality. Reviewed range 63db4bb..4914d8e and relevant current runtime paths. Application source was not changed by this review.

| Spec requirement | Status | Evidence |
| --- | --- | --- |
| Diagnose right-Command failure with counters | Incomplete | No three-counter packaged reproduction supplied. Existing edge logs are not the required diagnosis. |
| Failed meeting must release gesture | Partial | New recoverFromFailedStart checks session kind; hold and double-tap recovery unit cases exist. Actual coordinator/backend failure and tap-reset integration cases are absent. |
| Dedicated event-tap thread | Missing | HotkeyEngine installs both run-loop sources on CFRunLoopGetMain; watchdog uses the main queue. Existing watchdog/tap options were preserved. |
| Immediate cold capture | Partial | Capture consumer starts before ASR warm-up, but start still awaits enhancer.begin before consumeCapture. Enhancement can await Core ML loading. No packaged <100 ms result. |
| Bounded, loss-aware recognition gate | Missing | bufferingNewest(4096) discards oldest entries on overflow; feed.yield result is ignored. No journal-only overflow/recovery transition. |
| ASR-only prewarm readiness | Implemented in code | performWarmUp now returns without waiting for optional enhancement. Session startup itself still waits for enhancement. |
| Cleanup ablation and true-raw fixtures | Missing evidence | No ablation/MeaningValidator/SegmentCarry implementation located in searched source; no V0–V6 table or sweep results found in STATUS. |
| Conservative disfluency | Noncompliant | Tier0Adapters sets legitimatePairs=[]; TextDisfluencyStage permits any unprotected nonnumeric word. Spoken number words and legitimate doubles remain vulnerable. This predates this pull. |
| Meaning validator with hard carriers | Missing | CleanGuard checks marked literals, numeric/file literals and gross shortening, but does not reject negation or quantifier deletion. This predates this pull. |
| Chunk/context handling | Partial | Current token-bounded concurrent cleanup exists; no new segment carry, reference-based sweep or benchmark is included in this pull. |
| GPU default and pinned prompt | Preserved by pull | No ASR compute or prompt changes in reviewed diff; factory still defaults to cpuAndGPU. |
| Load/long-audio/contention evidence | Missing | No new first/second/rebuilt launch timings, 1/5/10-minute benchmarks or contention sweep in this diff. |
| Issue tracking | Incomplete before review | Existing issue.md did not record these backend gaps or the failing CI build. Review records confirmed significant blockers as Unresolved. |
| History keyboard changes | Reasonable, separate scope | Model owns bounded selection; AppKit handles arrows/Enter/Escape. New test has only one history row, so both arrows remaining at zero do not prove multirow navigation. GUI behavior untested here. |
| Composition expectation | Reasonable | Adds the already-present structure stage to the expected stage list. |
| CI configuration | Runs, but fails | Runner and Swift 6.4 checks succeeded. make verify failed building DeepFilterNet-mlx due to MLXArray captures in Sendable closures. |

## Findings to resolve before approval

1. High: mandatory CI remains red. [Run 41356842540](https://github.com/duggal1/superflow-2/actions/runs/41356842540) reached verification and failed compiling DeepFilterNetModel+Streaming.swift (including lines 791, 1760–1761). This is a dependency/toolchain compatibility failure, not evidence the new gesture tests fail.
2. High, existing: CleanGuard accepts polarity-changing edits such as removing `not` from an unprotected short sentence: no hard negation/quantifier/name comparison exists. The spec explicitly rejects this.
3. High, existing: cold-buffer overflow drops audio from recognition without surfacing it. The journal may retain it, but no automatic recovery transition makes the live transcript complete.
4. Medium: moving enhancement off prewarm is useful but does not establish immediate capture: enhancer.begin can load/await the enhancer before capture consumption starts.
5. Medium coverage gap: new tests invoke recoverFromFailedStart directly. They do not test a throwing meeting backend through the app entry point, a tap reset, or physical right-Command then Fn repetitions.
6. Minor: the changed warm-up error string contains a literal escaped interpolation, so the actual localized error will not be displayed. No issue entry required for this minor finding.

## Verification

- GestureKit GestureTests: 21 passed, including both new failed-start recovery tests.
- Session startup: 3 targeted tests passed (prewarm without warming state, capture before model warm-up, retry after warm-up failure).
- CI logs inspected: latest revision failed; runner/toolchain checks passed.
- UNTESTED: packaged gesture behavior, history GUI behavior, cold listening latency, overflow recovery, real cleanup fidelity, launch benchmarks and ASR/LLM contention.

The spec also needs care: rejecting every added newline conflicts with S1 lists/email formatting; raw negation/number counts can reject explicit spoken corrections. Validate those rules on owner-approved fixtures rather than copying the snippets verbatim. Keep GPU default, pinned prompt and privacy requirements.
