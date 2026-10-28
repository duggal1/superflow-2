# ADR 0014: Nemotron 3.5 tier and compute units for the default profile

Status: Accepted (measured, 2026-10-27, Apple M1 / 8 GB); GPU default set by owner, 2026-10-29

- Default profile is `nemotron-3.5-asr-streaming-0.6b` at the **2240 ms** tier, model directory `latin/2240ms`.
- Default Core ML compute units are **`.cpuOnly`** on this machine, overridable with `SUPERFLOW_COMPUTE_UNITS=ane|gpu|all`.
- Measured, Release, 8.66 s clip, warm, 5 repeats: 1120 ms CPU 12.7x, GPU 10.9x, ANE 2.8x; 2240 ms CPU 22.4x median, 119 ms/chunk, 115 ms stop-to-text, 45 MB footprint.
- Rationale: Core ML splits this mixed-precision int8 encoder on the M1 ANE, making the ANE path 4.5x slower than CPU. Vendor ANE numbers (66x-243x) are M2/M5-class.
- Consequence: the plan's "ANE-resident" assumption is false for this hardware/model pair; revisit on M2+ or if an ANE-native export appears. 300x RTFx is not attainable here (best 22.4x; 300x needs 3.7 ms per 2240 ms chunk).

Update 2026-10-29 (owner decision): the default Core ML runtime is **`.cpuAndGPU`** — the GPU
product path for the always-hot dictation experience, chosen by the owner for latency and
responsiveness, not from a throughput benchmark. The 2026-10-27 CPU measurements above stand as
recorded (`.cpuOnly` remains the throughput leader on this machine and stays available as
`SUPERFLOW_COMPUTE_UNITS=cpu`; ANE stays excluded). The VAD loads with the recognizer's policy so
VAD and encoder never cross runtimes mid-recording, device selection is resolved once per model
load (no runtime switching, no repeated warm-up specialization), and a unit test pins the default
and the alias table. Revisit the default when a GPU measurement exists at the 2240 ms tier and the
CPU/GPU ranking changes.
