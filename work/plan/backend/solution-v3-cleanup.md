# Cleanup v3
Root cause: the active pipeline schedules disfluency, polish and structure rewriting after S1-mini; its 1.5 s deadline and guard fallback rates are not measured.
- Replace those rewriting stages with protected, line-preserving post-dedupe; retain user commands, shortcuts, numbers, dictionary, code features and line formatter after S1-mini.
- Record content-free cleanup outcomes, token counts and latency through the existing diagnostics exporter.
- Verify stage order and adversarial dedupe cases, then affected package tests and lint.
- Preserve the exact S1-mini prompt, greedy runtime, GPU default and last-safe-text behavior.
- Packaged five-take evaluation, parity and later optimization gates require recorded input and owner-approved references; report them unverified until actually measured.

Current stage order with all relevant features enabled: cleanup, dedupe, commands, shortcuts, spokenCode, numbers, optional codeSpeak, lexicon, optional codeAware, lineformat. Number/lexicon are after S1-mini. No Harper/disfluency/polish/structure stages.
Metrics use the existing opt-in diagnostics export and expose accepted/rejected/deadline/cancelled/runtime_error/helper_unavailable events with numeric counts only. Prefill/generation timings are exported for completions that return; error and deadline timings remain whole-chunk only. Test fixtures are not yet available.
The required five packaged takes and owner-approved references have not been supplied; the matrix, parity, dynamic deadline, prefix caching, carry, sweeps, and any 9/10 claim remain unverified and unimplemented.
Runtime source audit: greedy sampler only, special-token parsing enabled, `llama_vocab_is_eog` stops generation, 4096-token context and 512-token prefill batches. The installed `llama-server` reports build 9330; app uses b11556. BOS parity, pinned-build server comparison and byte-identical output remain UNTESTED.
The helper protocol now reports per-completion prefill/generation durations without text; completion errors do not carry phase timings.
