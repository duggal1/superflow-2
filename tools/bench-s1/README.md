# bench-s1 — opt-in offline S1-mini latency probe

Pure Python stdlib. No third-party packages, no network egress, no model
download, no auto-run, no production data.

## Files

- `bench.py` — the probe. Enforces opt-in, drives bounded batches, writes JSON.
- `test_bench.py` — 14 offline unit/fake-server tests. Never loads a model.
- `README.md` — this file.

## Verify the tool without loading a model

    python3 tools/bench-s1/test_bench.py

This exercises prompt construction, the documented server flags, percentile
math, tokens/s, batch caps, opt-in refusal, and a fake loopback HTTP server.
It does not start the real `llama-server` and does not read a GGUF.

## Run the probe (explicit consent required)

    python3 tools/bench-s1/bench.py               # prints refusal, exits 2
    python3 tools/bench-s1/bench.py --i-opt-in    # starts server + loads model

Flags of interest:

| Flag | Purpose |
|---|---|
| `--i-opt-in` | Required consent. Without it nothing starts. |
| `--model PATH` | Locally installed Q4_K_M GGUF (read-only). Default: `~/Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf`. Env: `SUPERFLOW_BENCH_MODEL`. |
| `--base-url URL` | Use an already-running loopback server instead of starting one. Non-loopback URLs are refused. |
| `--input-file FILE` | Offline JSON list of transcript strings (or `{"transcripts": [...]}`). Default: 20 embedded synthetic fixtures. |
| `--outdir DIR` | Result directory. Default: `docs/benchmarks/results/`. |
| `--batch-size N` | Calls per batch, 1–10 (default 5). Values > 10 are rejected. |
| `--batch-pause-s S` | Pause between batches (default 1.0). |
| `--max-tokens N` | Per-call `max_tokens` (default 512). |
| `--total-cap-s S` | Whole-run wall clock cap (default 300). |
| `--hash-model` | Also SHA-256 the GGUF (read-only; slower). |

## What is measured

Only isolated `POST /v1/chat/completions` latency on loopback, with the pinned
system prompt + control line and the documented thinking-off/greedy flags.
Per-call latency, prompt/completion tokens, p50/p95/p99 of latency, and
end-to-end output tokens/s (plus server-reported decode tokens/s when the
server supplies `timings`) go into the result JSON.

## What is NOT measured

key-down→capture, first partial, stop→paste, RTF, warmup, ASR, text pipeline,
guard, XPC, or UI. A result here is not a "hyper-ultra-fast" proof. See
`docs/benchmarks/README.md` and `docs/benchmarks/audit-unverified-claims.md`.
