# Result files

Intentionally empty. A file appears here only when a user explicitly runs

    python3 tools/bench-s1/bench.py --i-opt-in

Each `s1-<UTC>.json` records isolated llama-server completion latency (per-call
values plus p50/p95/p99 and tokens/s) with its `claim_scope` and `status`.

A result here can move only the **"Isolated S1-mini completion"** row of the
parent README from UNVERIFIED to MEASURED. It does not measure key-down→capture,
first partial, stop→paste, RTF, or warmup.
