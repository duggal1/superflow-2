# ADR 0004: Enforce transcript storage privacy at the repository boundary

**Status:** Accepted

## Decision

The app wraps the SQLite transcript repository with `PrivacyRepository`. When `noTranscriptStorage` is enabled, session metadata and aggregate statistics remain available, while transcript segments and speaker labels are neither written nor returned.

## Context

The setting is runtime-configurable and both session and meeting engines share the transcript port. Enforcing the choice at the L5 repository boundary applies the same behavior to both engines without adding privacy branches to either engine.

## Consequences

The setting takes effect for subsequent repository calls. Existing stored transcripts are not removed when the setting is enabled.
