# Superflow architecture

Superflow records and streams audio locally. `AudioCppRecognizer` provides live ASR. `SessionEngine` owns dictation and streams completed text into cleanup. For dictation, the cleanup pipeline can begin processing sentences while ASR keeps streaming. The engine reuses a cleaned prefix only when its raw words match the final recognizer segment. The remaining tail goes through the normal cleanup queue. Domain contracts are in Kernel and Ports. See [the engine plan](plan.md) and [module dependencies](docs/architecture/module-dependencies.mmd).

The app builds the text pipeline with `CleanupService` and `LlamaCleaner`. In production the cleaner reaches llama.cpp through the InferenceHelper XPC service. Cleanup uses the pinned S1-mini model, protects exact literals and numbers, validates model output, and reports why it falls back. The app keeps the original text when a guarded model attempt cannot be used.
