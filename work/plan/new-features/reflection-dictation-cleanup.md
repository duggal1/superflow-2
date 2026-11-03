# Reflection cleanup for dictation

## Goal
Allow dictation cleanup to use Reflection's Beam model when explicitly enabled, while keeping S1-mini as the default and preserving deterministic post-cleanup stages.

## Invariants
- Reflection is opt-in, dictation-only, and reads the existing Reflection key from Keychain.
- Missing credentials or provider failures return the last safe transcript; they never switch to S1-mini while Reflection is selected.
- Post-deduplication and formatting stay in their current pipeline positions.

## Changes
1. Add a default-off persisted setting and expose an opt-in switch in Dictation settings with Keychain connection status.
2. Extend the existing Reflection completion client with per-request temperature and output-budget options.
3. Adapt Reflection to `TextCleaner`; use Beam-1.0-501B-A23B, low reasoning, and temperature 0.2.
4. Build separate dictation and meeting pipelines so only dictation uses Reflection.

## Verify
- Build the affected Swift packages and app target.
- Inspect the final diff and confirm no request occurs when the setting is off.
