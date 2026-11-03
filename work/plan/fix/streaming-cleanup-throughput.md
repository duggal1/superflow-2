# Streaming and cleanup throughput

Root cause: ASR blocks S1 warm-up, and the 250-token chunk target keeps typical longer segments on one worker.

- Start installed S1 warm-up alongside streaming ASR prewarm; preserve the API toggle and GPU selection.
- Use a 64-token cleanup target, retain protected spans, list continuity, acceptance gates, and bounded workers.
- Verify the existing single/parallel chunk behavior, real S1 parallel output, and targeted cleanup/session tests.
- Measure GPU inference on synthetic text; avoid claiming end-to-end latency or speedup without comparable runs.
- Inspect app build and actual settings; do not stage unrelated working-tree edits.
