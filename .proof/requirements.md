1. Make the 60-second @2x dictation replay finish: zero unfinished cleanup segments at stop, every source word retained.
2. Reduce 60-second stop-to-insertion to hyper-fast real latency (sub-second target), measured on the real Nemotron + S1-mini + SessionEngine pipeline.
3. Prove it with repeated headless replays of the real 60-second WAV at 2x pace, with millisecond timings, output checks, and fallback/error counts.
4. Add regression tests for the root cause; all affected suites must pass with no weakened or deleted tests.
5. Produce a before table and an updated after table in .proof/results.md, with no fabricated numbers.
6. Keep unrelated background work running, use no subagents, commit and push to main.
