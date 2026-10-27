# ADR 0010: Port contracts as reusable TestKit suites

**Status:** Accepted

## Context

PLAN.md section 20 requires one contract suite per port, run against both the
TestKit fake and the real adapter. Duplicating those assertions in every adapter
package lets the copies drift, and putting XCTest types in `TestKit` would make
the production support library depend on a test framework.

## Decision

- Implement each contract as a public, `Sendable` struct with a `verify` method
  that throws `ContractFailure`. `TestKit` does not import XCTest.
- Provide `contractRequire` for readable failures and `ContractStream.collect`
  with a timeout so a broken `AsyncStream` fails instead of hanging the suite.
- Keep the contracts behavioural: ordering, idempotent stop, error surfacing,
  bounded buffering, empty-input handling, secure-field blocking, and
  persistence round-trips. They do not assert private implementation details.
- Run every contract against the fake in `TestKit`'s own tests. Adapters add
  `SuperflowTestKit` to their **test target only** and invoke the same contract
  against the real implementation.
- Cover these ports: `AudioSource`, `SpeechRecognizer`, `SpeakerDiarizer`,
  `TextCleaner`, `GrammarChecker`, `TextInserter`, `TranscriptRepository`,
  `SettingsStore`, `ModelProvider`, `HotkeySource`, and `PermissionGate`.
- Add `FakeSpeakerDiarizer` so the diarization contract has a fake to run
  against, matching the other ports.

## Consequences and limits

- An adapter now needs a test-target dependency on `TestKit`. That is deliberate:
  the production target stays free of test code.
- Contracts catch port-level regressions, not adapter-specific bugs. Each adapter
  keeps its own unit tests (for example the SQLite migration suite and the
  pasteboard snapshot tests).
- A contract cannot prove hardware behaviour. `HotkeySourceContract` cannot
  install a real event tap in CI, and `SpeechRecognizerContract` cannot prove
  Core ML accuracy; those remain integration/soak and manual checks.
- Changing a contract is a cross-package change: every adapter test must still
  pass. Keep contract changes small and justified by the port, not by one
  adapter's convenience.

## Evidence

- `swift test --package-path Packages/L0-Core/TestKit`: 22 tests, 0 failures.
- `swift test --package-path Packages/L1-Adapters/StorageSQLite`: 24 tests,
  including `testSQLiteSatisfiesTranscriptRepositoryContract` and
  `testSQLiteSatisfiesSettingsStoreContract` against real SQLite.
- `swift test --package-path Packages/L1-Adapters/TextInsertion`: 9 tests,
  including `testSystemInserterSatisfiesTextInserterContract`.
