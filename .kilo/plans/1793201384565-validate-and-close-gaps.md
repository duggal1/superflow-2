# Validation and Remaining Gaps Plan

## Goal
Validate the implemented TextInsertion upgrade and elite cleanup pipeline against the two plans, and close only the remaining, measurable gaps without adding bloat.

## Current State
- TextInsertion backend (`Packages/L1-Adapters/TextInsertion`) already implements the required decision tree: AX-first for confident editable controls, transient pasteboard + synthetic Cmd+V fallback, adaptive restore (50 ms confirmed / 500 ms last-resort), 30 s prepared PID TTL with invalidation, whole-value verification primary with count secondary, actor serialization, secure-field blocking, and SyntheticInputMarker stamping. ADR 0022 and PLAN.md §15 already reflect this.
- Cleanup pipeline stage order, ProjectContext injection, TextDisfluency, TextCodeAware, CleanupStructure list detection, TextGrammarGate policy, and TextLineFormat code protection are implemented and documented in ADR 0021.
- Golden suites and soak harness exist; a 10-hour soak and fine-tune are optional/remaining.

## Validation Tasks (run first)
1. Run `make verify` (or `make build && make lint && make test-fast`) and capture failures.
2. Run TextInsertion package tests: `swift test --package-path Packages/L1-Adapters/TextInsertion`.
3. Run Golden tests that require models separately (`make test-models`) and confirm Harper precision >= 98% on the bundled corpus.
4. Confirm no file exceeds 400 lines and no layer violations (`make lint`).

## Remaining Implementation Gaps
- Fine-tune path: collect owner dictations + synthetic hard cases and run a LoRA experiment on Qwen3-0.6B/S1-mini; only swap if it wins on the golden set.
- Soak: complete 10-hour RSS/zero-loss assertions in `Tests/Soak` and run one real-time overnight pass.
- Harper: run the category precision report and disable any category below 98%; record results in the golden suite.
- Back-pressure: current serialization is acceptable; add an explicit coalescing test for rapid consecutive insertions if not already covered.
- Restore: keep the 500 ms window as true last resort only; add a test proving it is never used after a verified insertion.

## Out of Scope
- No new dependencies or third-party libraries.
- No general chat model on the live path.
- No whole-filesystem indexing.

## Definition of Done
- `make verify` green.
- All existing tests pass; new validation tests pass.
- ADRs and PLAN.md unchanged except where a measured result requires an update.
