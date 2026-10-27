# ADR 0014: Nemotron 3.5 tier and compute units for the default profile

Status: Accepted (measured, 2026-10-27, Apple M1 / 8 GB)

- Default profile is `nemotron-3.5-asr-streaming-0.6b` at the **2240 ms** tier, model directory `latin/2240ms`.
- Default Core ML compute units are **`.cpuOnly`** on this machine, overridable with `SUPERFLOW_COMPUTE_UNITS=ane|gpu|all`.
- Measured, Release, 8.66 s clip, warm, 5 repeats: 1120 ms CPU 12.7x, GPU 10.9x, ANE 2.8x; 2240 ms CPU 22.4x median, 119 ms/chunk, 115 ms stop-to-text, 45 MB footprint.
- Rationale: Core ML splits this mixed-precision int8 encoder on the M1 ANE, making the ANE path 4.5x slower than CPU. Vendor ANE numbers (66x-243x) are M2/M5-class.
- Consequence: the plan's "ANE-resident" assumption is false for this hardware/model pair; revisit on M2+ or if an ANE-native export appears. 300x RTFx is not attainable here (best 22.4x; 300x needs 3.7 ms per 2240 ms chunk).
