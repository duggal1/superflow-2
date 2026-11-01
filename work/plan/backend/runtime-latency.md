# Backend latency and input reliability

- Scope: preserve Nemotron 3.5, FluidAudio/Core ML, S1-mini and llama.cpp.
- License: Hex MIT, copyright Christopher Langton 2026; preserve notice for ports.
- Baseline: existing CLI binary differs from source; rebuild before comparisons.
- Investigate: separate cached model initialization, specialization, first inference,
  cleanup, and insertion; do not attribute end-to-end latency to GPU without evidence.
- Model work: inspect ASR loader/pool, launch/session lifecycle and cleanup runtime;
  fix proven redundant work and retain residency; record measured limitations.
- Verify: release CLI with real audio, ASR and cleanup regressions, cached relaunches.
- Insertion work: inspect AX inspection/baseline, paste posting, focus and restore;
  remove proven redundant blocking work without risking duplicate insertion.
- Verify: TextInsertion tests, clipboard/focus/failure regressions; native probe if permitted.
- Hotkey work: compare Hex physical modifier flags and gesture timing with Superflow;
  fix proven edge/state/permission faults without changing shortcut semantics.
- Verify: mapper, GestureKit and app input tests; distinguish physical keys from fakes.
- Meetings: inventory only; identify complete implementations, existing equivalents,
  privacy/runtime conflicts and port effort. Await approval before feature ports.
- Finish: app build, required architecture gates and applicable tests, review owned diff.
- Commit each workstream separately on fix/backend-runtime-latency; preserve unrelated edits.
- Record evidence and inventory in agents/codex/backend-runtime/results/report.md.
- Solution phase 0: add model-load and stop signposts, insertion-return and
  microphone-open/first-feed timings; test success and failure attribution.
- Reuse the existing load probe for CPU/GPU/ANE/all; do not synthesize model inputs.
- Record known baseline data and explicitly missing measurements in docs/perf.
- Gate later behavior changes on a complete packaged-app baseline and quality data.
