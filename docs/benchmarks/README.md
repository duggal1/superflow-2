# S1-mini benchmarks — measurement, not marketing

This folder makes S1-mini speed **measurable and honest**. Nothing here is
auto-run. No number in this folder is a claim until a row below says
**MEASURED** with a result file to back it.

The isolated latency probe is [`tools/bench-s1/bench.py`](../../tools/bench-s1/bench.py).
It is opt-in, offline, and writes result JSON to [`results/`](results/).
Read its own [README](../../tools/bench-s1/README.md) before running it.

## Official reference numbers (vendor-published, NOT measured here)

These come from the official **superwhisper/s1-mini v1** model card and the
repo's own pinned constraints. They are *reference context only*. They are not
local measurements, not evidence of this build's speed, and not proof of any
"hyper-ultra-fast" claim.

| Reference | Official value | Status here |
|---|---|---|
| Token accuracy | **94.8%** on **7,519** cases | UNVERIFIED locally — vendor model-card figure, not reproduced in this repo |
| Weight size | **462 MiB** Q4_K_M GGUF | Reference only — the installed file is 484,219,808 bytes (~461.8 MiB) on disk; disk size is neither memory footprint nor throughput |
| Recommended input length | **~1,000 tokens** per chunk | Reference only — the app's 850-token hard cap sits under this; larger inputs or more workers do not guarantee higher throughput |

Source of the repo-side constraint wording:
`work/plan/backend/2026-11-05-streaming-s1-island-reliability.md:42`.
Model attribution/license: `docs/licenses/S1-mini-NOTICE.txt` and
`S1-mini-LICENSE.txt` ("S1-mini by Superwhisper").

## Results table — all cells currently UNVERIFIED

"MEASURED" means an explicit, opt-in run produced a result file in `results/`
for that exact stage on this machine. "UNVERIFIED" means no such evidence
exists. An empty cell is not a number and must never be quoted as one.

| Stage / metric | What would count as MEASURED | Status | Evidence |
|---|---|---|---|
| key-down → capture | First audio sample captured after key-down, p50/p95/p99 over N runs, headless with real capture path | **UNVERIFIED** | none — `bench.py` does not touch capture |
| first partial | First non-empty partial transcript after key-down, p50/p95/p99; bounded by the real ASR chunk tier | **UNVERIFIED** | none — `bench.py` sends completed text only |
| stop → paste | Stop key to text visible in the document, p50/p95/p99, including guard/pipeline/insert | **UNVERIFIED** | none — `bench.py` excludes pipeline and UI |
| RTF (real-time factor) | Processed audio seconds / wall seconds on the release product path, p50/p95 | **UNVERIFIED** | none — no audio path in `bench.py` |
| warmup | Cold process → model ready (load + prewarm), separate from steady state | **UNVERIFIED** | none — `bench.py` excludes load/prewarm |
| Isolated S1-mini completion | llama-server `/v1/chat/completions` latency, p50/p95/p99, tokens/s | **UNVERIFIED** | no opt-in run has been recorded in `results/` |

When a user runs the probe, only the **last** row can become MEASURED. The
first five still require separate product-path harnesses. Do not promote an
isolated completion number into an end-to-end speed claim.

## Run the isolated probe (opt-in only)

```sh
# from the repo root
python3 tools/bench-s1/test_bench.py          # verifies logic with a fake server; NO model load
python3 tools/bench-s1/bench.py               # refuses to run — prints opt-in warning
python3 tools/bench-s1/bench.py --i-opt-in    # only now: starts llama-server, loads the GGUF
```

The probe:

- starts `llama-server -m <Q4_K_M gguf> --jinja --chat-template-kwargs
  '{"enable_thinking":false}' --temp 0 -c 2048` bound to `127.0.0.1`;
- sends the exact pinned system prompt and control line
  `[Styling: semi-formal] [Structure: lists] [Context: general]`;
- drives batches of at most 10 calls, 30 s per-call cap, ~300 s total cap;
- records per-call latency plus p50/p95/p99 and tokens/s to
  `docs/benchmarks/results/s1-<UTC>.json`;
- never downloads, never reads owner/user data, and stops only the server it
  started.

`--base-url` targets an already-running loopback server; `--input-file` accepts
an offline JSON list of transcripts. Full flag list: `bench.py --help`.

## Eager prewarm hook — how to call it (no API changes)

`App/InferenceHelper` already exposes an eager model-prewarm hook. It is the
XPC protocol method `prepareModel(atPath:gpu:reply:)`:

- declared in
  `App/InferenceHelper/Sources/SuperflowInferenceHelperProtocol/InferenceHelperProtocol.swift:16`;
- implemented in
  `App/InferenceHelper/Sources/SuperflowInferenceHelperCore/InferenceHelperService.swift:22`.

Call it with the verified local GGUF path and the desired compute placement;
it loads the model into the helper's runtime and calls back `(Bool, String?)`.
`true, nil` means the model is warmed and ready; `false` carries an error
string. This is the hook that should be invoked before a latency measurement
if warmup is ever to be marked MEASURED — but note that `bench.py` deliberately
does **not** call it, because `bench.py` measures isolated server completions,
not the helper path.

```swift
// Given a connected XPC proxy `helper: InferenceHelperProtocol`:
helper.prepareModel(atPath: verifiedGGUFPath, gpu: true) { ready, error in
    if ready { /* model is warm and ready */ }
    else { /* handle error ?? "" */ }
}
```

`gpu: true` places weights on Metal (matching the product default);
`gpu: false` keeps them on CPU. The helper reloads when the loaded model
differs from the requested one. No package API was changed to support this
documentation.

## Audit

See [`audit-unverified-claims.md`](audit-unverified-claims.md) for the list of
speed claims currently scattered across `.proof/performance/` and
`docs/STATUS.md` that must not be repeated as fact.
