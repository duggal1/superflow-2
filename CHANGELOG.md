# Changelog

## Tech dictionary v4 (post-ASR replacement)

- Migrated `Packages/L2-Engines/catalog/tech-dictionary.json` (v3) to `vocab_v4.json` (v4) with typed entries, Tier A/B aliases, gating metadata, and deterministic collision resolution.
- Before: 687 entries / 3405 aliases. After: 452 entries / 2252 aliases (Tier A + Tier B).
- Added `scripts/audit_vocab.py` and `scripts/migrate_v3_to_v4.py`; audit artifacts under `audit/`.
- Wired `vocab_v4.json` into the dictation pipeline via `TechDictionary` and `TechDictionaryGate`; Tier B aliases are context-gated.
- Added active-application, project-vocabulary, pinned-term, and dev co-word gating; textract resolves to "tech stack" unless AWS/document context is present.
- Added `activeAppBundleID` to `TextContext` for the dev-app gate.
- Identifier Mode remains in `TextCodeSpeak` (camel/snake/pascal/kebab/constant case).
- Eval gate: `Tests/.../DictionaryEvalTests.swift` with `negatives.txt` (>=300) and `positives.txt` (>=300).
