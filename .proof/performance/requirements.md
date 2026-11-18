# Requirements — Agent 6 performance / audio / HEX-port task

Scope ownership: `Packages/L1-Adapters/LLMLlamaCpp/**`, `Packages/L2-Engines/AudioEnhancement/**`,
`Packages/L1-Adapters/AudioCapture/**`, `Packages/L1-Adapters/AudioCpp/**`,
`Packages/L1-Adapters/SystemAudioCapture/**`, new L2 speech-frontend packages,
`.proof/performance/**`, and only new-dependency lines in `App/SuperflowApp/Package.swift`.

1. Root-cause S1-mini failures with hard evidence from the real installed GGUF at
   `~/Library/Application Support/Superflow/Models/s1-mini-q4-k-m/s1-mini-q4_k_m.gguf`.
2. Measure BEFORE latency/failure at 10 s, 30 s, 1 min audio-equivalent lengths. 10 min is
   NOT MEASURED directly (coordinator cap); a short synthetic equivalent is labelled as such.
3. Fix S1 reliability: no silent fallbacks, warm-up must not crash, no spurious token-cap
   truncation, errors propagate as typed `SuperflowError`.
4. Make S1 fast on Apple Silicon with bounded workers (M1/8 GB), GPU placement, context reuse,
   bounded batching, parallelism that fits the machine.
5. Root-cause the low capture→enhancement→recognizer audio path with evidence.
6. Implement a real VAD (HEX ideas: energy/ZCR, 160 ms min speech, 0.4 threshold, silence-gated
   gain) plus measurable loudness/AGC tests with low-volume and noisy fixtures.
7. Port HEX ideas (silence-point chunking, vocabulary boost/sounds-like handling, benchmark
   method with warmup+JSONL+RTF) into owned Swift packages with tests; document source.
8. Verify: `swift test` for every owned package with counts, `tools/lint-forbidden` clean,
   `swift build --package-path App/SuperflowApp --configuration release` green, benchmarks JSON.
9. Deliver `.proof/performance/report.md` with BEFORE/AFTER tables, failure-rate evidence,
   audio numbers, HEX ports, test/lint/build evidence, and honest UNVERIFIED items.
10. Obey coordinator safety: build fence, one heavy process, --jobs 1/2, ≤30 s inference,
    one duration per batch, 5-min kill, load-average watch, fewer workers.

Baseline (2026-11-18, M1 8 GB, 484 MB q4_k_m GGUF, debug build):
- default 6 sessions GPU: warm-up aborts with `llama.cpp failed while generating cleanup text` (~36.6 s).
- 4 sessions: 4/8 cases failed; 1/2 sessions: 2/8 failed (the 1.5 s-deadline cases ≥30 s audio).
- 1 min audio at 30 s deadline: `hitTokenCap=true` (227 out for 150 in) = truncation.
- generation dominates (537 ms/27 tok; 1631 ms/82 tok; 4774 ms/227 tok); prefill 5–16 ms.
