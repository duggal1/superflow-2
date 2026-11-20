# brutal-s1 — aggressive offline S1-mini quality probe

Pure Python stdlib. Headless, opt-in, loopback-only, no downloads. Drives the
**installed** S1-mini Q4_K_M through `llama-server` with the exact pinned system
prompt + control line and greedy decoding, then scores ultra-broken transcripts.

## Run

    python3 tools/brutal-s1/brutal_s1.py              # prints refusal, exit 2
    python3 tools/brutal-s1/brutal_s1.py --i-opt-in   # loads model, runs 21 cases
    python3 tools/brutal-s1/brutal_s1.py --i-opt-in --case list_dash_spoken

Nothing happens without `--i-opt-in`. The server this script starts is the only
process it stops. Results go to `.proof/brutal-s1/brutal-<UTC>.json` and `.txt`.

## What it measures

- Per-case grammar/fact/formatting score (required + forbidden tokens, dash-bullet counts, final punctuation, no fillers).
- Isolated latency p50/p95 and streaming time-to-first-token on three cases.
- Exact prompt contract: `[Styling: semi-formal] [Structure: prose|lists] [Context: general|email]`.

## What it is NOT

Not an end-to-end dictation WER, not ASR accuracy, not key-down→paste latency.
App-path formatting is verified separately by the Swift tests in
`Packages/L2-Engines/TextPipeline/Tests/TextPipelineTests/BrutalFormattingProbeTests.swift`.

## Disk safety

Only the 462 MiB model is read (read-only by the server). No build artifacts,
no model download, no user corpus. A full run finishes in well under 300 s with
a 0.2 s pause between calls so the Mac stays responsive.
