# Text intelligence, Knowledge, and streaming Models execution
Baseline: main 31afde680d07d35bec431ad65a48114dfe573413. Preserve all current work and schema.
1. Verify current CI and identify reproducible audio.cpp/Metal failure. Never skip a failing test as a fix.
2. Add a bounded model-family/version parser (25+ families) after cleanup and before the final dictionary; negative corpus.
3. Improve explicit spoken list structure, preserving model-created paragraphs and guarded content; regression corpus.
4. Add contextual filename and Git command rewriting without executing or inventing commands.
5. Extend dictionary models/schema with safe migrations, per-app scope, learning candidates and metadata; preserve data.
6. Add a bounded edit-learning observer with consent, AX secure-field checks, local diff, confirmation, Undo.
7. Reuse existing Island notifications and completion sound on committed learned changes.
8. Combine Dictionary and Shortcuts under one Knowledge route and page while preserving both services and import/export.
9. Move speech activation from Settings to Models. Make search and installed/active states real.
10. Audit audio.cpp's actual streaming C ABI, models, licensing, pinned assets, and native Metal capability.
11. Add only model runtimes that can really transcribe during capture and have reproducible verification.
12. Benchmark each eligible ASR model on the same Mac; show no invented quality score.
13. Profile and tune bounded parallelism; do not block audio journaling or overwhelm GPU.
14. Verify focused Swift tests, design states, app build, full CI, release packaging and live hardware when available.
15. Review diff, branch/PR checks, and merge only verified work. Record unresolved external/hardware gates.
