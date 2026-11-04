# Streaming ASR models continuation

Baseline: main 618f802e75a79054f8312e426d99d69df3349aef (merged text/Knowledge work).
Root cause: the Models page has one speech row and AudioCppRecognizer hardcodes a single Nemotron runtime.
Scope (do not alter unrelated feature work):
1. Verify pinned audio.cpp streaming C ABI and candidate GGUF artifacts, hashes, license.
2. Introduce typed streaming ASR profiles with real runtime mapping and immutable artifact metadata.
3. Preserve installed Nemotron paths; use per-profile native session caches and checksums.
4. Update native CMake for only the integrated families; retain Metal default.
5. Generalize AudioCppRecognizer runtime selection, warmup, download, stream, and cancellation.
6. Make Models page list all genuinely integrated models with independent state, search, activate, and model removal.
7. Keep default Nemotron if alternate model is absent/fails; never swap mid-session.
8. Show honest quality status (Not benchmarked until measured); retain bounded parallelism.
9. Add focused mapping, catalog, artifact and model-selection regression tests.
10. Review Swift API compatibility, dependencies, and UI accessibility. Real Mac inference tests remain a release gate.
11. Commit each scoped change on this branch and merge only after verification.
