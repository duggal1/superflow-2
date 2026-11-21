1. Reduce end-of-dictation latency for short, medium, and long speech by cleaning completed segments during capture.
2. Reuse S1-mini workers on one loaded model, comparing one and multiple real inference contexts within the Mac's resource limits.
3. Preserve raw speech order, technical text, sentence context, and safe fallback at boundaries. Keep model requests within the 800-token planning budget and hard limit.
4. Benchmark stop-to-insertion in milliseconds with real streaming ASR and S1-mini, including longer recorded speech, reporting fallback and memory.
5. Run solo, headless, and keep existing background work running.
