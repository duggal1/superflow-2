# Dictation release benchmark

Headless SessionEngine replay used real Nemotron and S1-mini with one inference context. Latency runs from engine stop through an in-memory insertion sink. Physical keyboard and target-app paste were outside this measurement.

| Audio | Legacy | Provisional sentence cleanup |
| --- | ---: | ---: |
| 10 seconds at 1× | 901–1,005 ms | 587–644 ms, zero unfinished segments |
| 30 seconds at 2× | 1,806 ms | 1,253–1,268 ms, zero unfinished segments |
| 60 seconds at 2× | 2,641 ms | 3,598 and 19,177 ms, unfinished cleanup on both runs |

A rejected approach finalized the native decoder about every eight seconds. It produced 481–590 ms on the short clip and 516–642 ms on the 30-second clip, but changed the latter's raw transcript and lost a word. The current implementation leaves the native ASR stream intact and reuses provisional cleanup only when the final text confirms the prefix.

The final change reuses matching model work that is still in flight. Its headless build passed. Replay and the additional worker trial were stopped before validation. The SSD had dropped below 1 GiB free earlier in the run.
