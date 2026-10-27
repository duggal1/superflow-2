# Backend Run Status

Updated: 2026-10-27

## Milestones

- **Done — S1-mini Q4_K_M download and smoke:** `.models/s1-mini/s1-mini-q4_k_m.gguf`, 484,219,808 bytes. SHA-256 `3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634` matches the Hugging Face LFS digest. `llama-server` loaded it and returned `So I need to send the report by Thursday.` for the model-card prompt; measured prompt evaluation 359.41 tokens/s and generation 100.86 tokens/s on this M1 Air. Model license and required “S1-mini by Superwhisper” attribution were read from the downloaded LICENSE.
- **Done — Nemotron 3.5 ASR Streaming 0.6B v1 download, verification, and FluidAudio smoke:** `.models/nemotron35/latin/1120ms/`, 22 bundle files plus README and manifest, 611,362,753 bytes. The 15 LFS SHA-256 hashes and 9 Git blob SHA-1 hashes match the pinned Hub revision. FluidAudio 0.17.7 loaded the compiled Core ML models and transcribed an 8.66-second generated clip as `Good morning, the product review is Thursday at ten thirty AM. Please send the notes to Morgan and include the updated budget of one hundred twenty five dollars`. First-run model loading took about 47 seconds in the Debug CLI; the next run processed this clip in 1.95 seconds (4.4x RTFx) and peaked at 2.486 GB RSS on the M1 Air. This confirms load and text output, not partial-arrival timing during playback.
- **Discarded — English-only Nemotron candidate:** the requested update selected the exact Nemotron 3.5 v1 model. The separate `FluidInference/nemotron-speech-streaming-en-0.6b-coreml` candidate was fetched and checksum-checked, but its first ANE compile ran for over five minutes without a transcript. It was canceled and removed; it is not counted as downloaded or usable. No model-load error was observed, so this is not an unusable-model conclusion.

## Current Work

- **Done — speed A/B on the real 0.6B model (Release, 8.66 s clip, warm, 5 reps).** Compute units matter more than anything else on this M1 Air: `.cpuOnly` = **12.7x RTFx** at the 1120 ms tier (88.5 ms/chunk), `.cpuAndGPU` = 10.9x, `.cpuAndNeuralEngine` = **2.8x** (417 ms/chunk). The ANE path is 4.5x slower because Core ML splits this int8 encoder; the vendor's 66x/243x ANE numbers are M2/M5-class only. Switching to the **2240 ms tier on CPU** (vendor-recommended tier, 565 MB, downloaded and verified loadable) gives **22.4x median** on the product default path, 115 ms stop-to-text, 119 ms per 2.24 s chunk, 45 MB footprint after warm-up, +0 MB growth. That is a 9x improvement over the 2.8x ANE default and replaces the earlier 3.9x 1120 ms Debug-era figure.
- **Done — `superflowctl bench`**: release-only small-clip harness (refuses Debug), 2 discarded warm-up passes, then N measured runs; reports RTFx, per-chunk p50/p95, stop-to-text, phys_footprint baseline/growth. Deliberately excludes journal and text pipeline so a slow stage cannot hide.
- **In progress — remaining model set:** Silero VAD present at `.models/silero-vad/` (8,370,975 bytes), not yet separately validated. EOU (438 MB) and Sortformer (235 MB) downloads look complete; Parakeet Unified (588 MB) still needs checksum verification. None are on the default path.

## Next

1. Extend the speed bench to 1 min and 5 min audio on the 2240 ms CPU profile, then a real-time run.
2. Try the 4480 ms tier (another 567 MB): halves encoder passes again; expected ~35-45x on this M1.
3. Profile the remaining 119 ms/chunk to separate encoder, mel front-end and decode-loop cost; evaluate FluidAudio's native-Swift mel extractor.
4. Fix the RSS baseline in `benchmark` (it still reports RSS growth from a pre-page-in baseline) to match `bench`'s phys_footprint accounting.
5. Read the complete repository and plan, produce the backend gap report, then continue implementation.

## Failing / Blocked

- **300x real time is not attainable for this model on this machine.** Best measured: 22.4x (2240 ms, CPU). Vendor's 243x is an M5 Pro at the same tier; 300x would need 3.7 ms per 2240 ms chunk versus the 119 ms measured here.
- No long-duration ASR or reliability assertions have been run. The 8.66-second transcript smoke and the speed bench are not soak evidence.
- The `joint_noencproj_batched` / `decoder_joint_noencproj` fast-decode assets are not published in the model repo, so FluidAudio logs `Smart-spec: assets missing` and uses its legacy inner loop. Impact not yet isolated.

## Backend test run (2026-10-27, this session)

- `Tests/Integration`: 5/5 pass.
- `Tests/Golden`: 70/70 pass (9 skipped).
- `Tests/Soak` (SUPERFLOW_SOAK_SECONDS=30, SUPERFLOW_SOAK_REALTIME=1): journal fully journaled/replayable pass (20.75s); accelerated vs real-time transcript row counts match pass (31.32s). No failures.
- Backend packages (L0/L1/L2/Superflowctl) build clean.
- `make verify` passed in full on 2026-10-27 (build, all package/app/helper/CLI tests, dependency check, forbidden-pattern lint). The frontend compile errors recorded earlier are resolved in the working tree: `swift build --package-path App/SuperflowApp --configuration debug` and the full gate both pass.
- Addendum A Phase 0b gate documented: ADRs 0015–0019 cover adoption/conflicts, the deferred local analyzer, the MCP server, detection/calendar/voice memory, and structure/candidate quality. Runtime spike evidence is still outstanding.
- Addendum A Phase 3b backend landed on 2026-10-27: `TextPipeline.explain()` with per-stage provenance, `TextCodeSpeak` (identifiers, paths, flags, bounded symbols, backticks and code blocks; opt-in, protected output, exact rule ids) and `ContextProfiles` (Writing/Chat/Code/Prompting, pure bundle/host resolver, `cleanupContext` now wired into cleanup). ADR 0020 records the grammar and guards. New packages: 13 + 14 tests; TextPipeline 20 tests. All opt-in features default off; `make verify` green after the change.
