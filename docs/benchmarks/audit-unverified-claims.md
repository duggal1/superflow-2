# Audit — speed claims that are currently UNVERIFIED

Purpose: stop anyone from repeating an agent-report or historical number as a
product fact. A claim is UNVERIFIED here if it is a smoke observation, a
superseded/historical measurement, gated behind an env flag, expressly labelled
UNTESTED, or measured on a different pipeline than the one now shipped.

Nothing in this note is a new measurement. Line references are to the checked
in files; if they move, re-audit rather than quote the number.

## From `.proof/performance/`

| Claim as written | Where | Why it is UNVERIFIED / not a product fact |
|---|---|---|
| "1.33× / 2.11× / 1.71× / 2.36× faster" S1 cleanup | `.proof/performance/report.md:60-65` | Fenced agent run at a **30,000 ms** deadline with 4 sessions, not the shipped **1,500 ms** deadline. Corroborating status marks the requirement PARTIAL / UNVERIFIED (`.proof/quality/final-status.md:13`). |
| 1 min cleanup "no longer truncates" / succeeds | `.proof/performance/report.md:64-65` | Succeeds only at 30 s budget; at the shipped 1,500 ms deadline it still times out (`:64`, `:165`). |
| Any 10-minute S1 latency | `.proof/performance/report.md:66`, `:164` | Explicitly **NOT MEASURED** (coordinator cap). |
| "1.33–2.36× faster" headline | `.proof/quality/final-status.md:13` | Status is **PARTIAL / UNVERIFIED**, not PASS. |
| Word-error rate / loudness as accuracy | `.proof/performance/report.md:121-122`, `:161-162` | **UNVERIFIED** — no labelled corpus or scorer; RMS/SNR are proxies only. |
| ANE placement | `.proof/performance/report.md:41`, `:163` | **UNVERIFIED / unavailable** — llama.cpp XCFramework exposes CPU/GPU only. |
| Chunked vs single-shot equivalence on real speech | `.proof/performance/report.md:167-168` | **UNVERIFIED** — ordering tested with a fake runtime, model-output equivalence not measured. |
| Historical uncontrolled 30 s probe (timed out at 31 s) | `.proof/performance/report.md:21-22` | Explicitly **not used as a baseline**. |

## From `docs/STATUS.md`

| Claim as written | Where | Why it is UNVERIFIED / not a product fact |
|---|---|---|
| "prompt evaluation 359.41 tokens/s and generation 100.86 tokens/s" | `docs/STATUS.md:22` | Single `llama-server` smoke observation, not a reproducible benchmark; no p50/p95, no batch size, no result artifact. |
| "five packaged-app takes, runtime parity, reference-based quality, 9/10 score, deadline/fallback rates, performance sweeps" | `docs/STATUS.md:14` | Explicitly **UNTESTED**; "no quality or speed improvement is claimed". |
| "12.7x / 10.9x / 2.8x RTFx", "22.4x median", "115 ms stop-to-text", "119 ms/chunk", "9x improvement" | `docs/STATUS.md:29`, reiterated `:43` | FluidAudio-era measurements. `docs/STATUS.md:5` says earlier FluidAudio measurements are **historical and superseded** by the current audio.cpp runtime. Do not present as current product speed. |
| "4.4x RTFx" FluidAudio smoke | `docs/STATUS.md:23` | Historical/superseded; smoke only, "confirms load and text output, not partial-arrival timing". |
| Vendor "66x/243x ANE" numbers | `docs/STATUS.md:29`, `:43` | Vendor figures on M2/M5-class hardware, **not this machine**, and not a claim about the shipped build. |
| "300x real time is not attainable ... best measured 22.4x" | `docs/STATUS.md:43`; `docs/adr/0014-nemotron-tier-and-compute-units.md:9` | About the historical/superseded FluidAudio path; not a current-path result. |
| Vocabulary hotword/correction "latency impact" | `docs/STATUS.md:18` | Explicitly **unmeasured** ("term recall, false-fire rate, grammar quality, and latency impact remain unmeasured"). |
| `superflowctl bench` harness exists | `docs/STATUS.md:30` | A harness is not a result; no release measurement artifact accompanies the claim here. |
| "No long-duration ASR or reliability assertions have been run" | `docs/STATUS.md:44` | Direct statement that soak evidence is absent. |

## Bottom line

- No file in this repo currently supports the phrase **"hyper-ultra-fast"** as a
  measured property of the shipped app. Treat it as an unverified marketing
  characterization until a row in `docs/benchmarks/README.md` says MEASURED.
- The official vendor references (94.8% / 7,519 cases, 462 MiB Q4_K_M, ~1,000
  token chunk) are model-card context, not local results.
- `tools/bench-s1/bench.py` can, on explicit opt-in, produce one honest number —
  isolated S1-mini completion latency. It cannot by itself verify any of the
  end-to-end stages above.
