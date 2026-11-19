# Seven-agent dispatch manifest — extreme quality task

Dispatch: coordinator launched seven sub-agents in parallel, each with the design
docs (`DESIGN.md`, `DESIGN-RULES.MD`, `DYNAMIC-ICELAND-DESIGN.MD`,
`dynmaic-island-intelligence.md`, `AGENTS.md`, `rules.yaml`, `git.yaml`) and a
strict no-smoke-test / headless / no-commit prompt. Peer handshake for agents 4/5
via contract files. This manifest exists because session IDs are not durable in
the tree; the file set below is the verifiable evidence of disjoint ownership.

| # | Agent | Session ID | Sole ownership (verifiable in git/proof) | Report |
|---|---|---|---|---|
| 1 | Transcription corpus A | `ses_e10bfddfaffeb2fwjr2r9c4xTu` | `AggressiveCorpusShortTests.swift`, `.proof/transcription-corpus/` | `.proof/transcription-corpus/agent1-report.md` |
| 2 | Transcription corpus B | `ses_e10bfddfaffdHBHPKeL7sYAA1O` | `AggressiveCorpusLongTests.swift`, `AggressiveCorpusDiversityTests.swift`, `.proof/transcription-corpus/agent2/` | `.proof/transcription-corpus/agent2-report.md` |
| 3 | Island bright/sharp/smooth | `ses_e10bfddf5ffe3DgZTIZQETwyOp` | `FeatureIsland` sources/tests (13 files), `.proof/island-bright/` | `.proof/island-bright/report.md` |
| 4 | Knowledge front-end | `ses_e10bfddd4ffeiwlyDr9emkBCC6` | `KnowledgeView.swift`, `KnowledgeNoticeRouter.swift`, `FeatureHistory`, `.proof/knowledge-front/` | `.proof/knowledge-front/report.md` |
| 5 | Knowledge back-end | `ses_e10bf80a4ffe1IUrs0fdp72fqW` | Dictionary, Shortcuts, learning engine, SQLite knowledge files, `.proof/knowledge-back/` | `.proof/knowledge-back/report.md` |
| 6 | Performance / S1 / audio / VAD / HEX | `ses_e10bf80a0ffeLmBl2GyuLEJAA3` | LlamaCpp, AudioEnhancement, AudioCapture, AudioCpp, SystemAudioCapture, `.proof/performance/` | `.proof/performance/report.md` |
| 7 | Crash recovery | `ses_e10bf8093ffeOw0wrgt4qIMffV` | `RecoveryEngine/**`, `.proof/recovery/` | `.proof/recovery/report.md` |

Coordinator (this session) owned integration, the number/punctuation fixes, the
build fence, the two-pass audit and git. No agent committed or pushed.
