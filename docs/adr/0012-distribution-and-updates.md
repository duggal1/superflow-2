# 0012. Distribution: Developer ID, notarized DMG, and the update path

Status: Accepted (2026-10-26)

## Context

Superflow cannot be sandboxed: the hotkey engine installs an event tap, text insertion posts
synthetic paste events, and meeting mode taps system audio. macOS ties privacy grants
(microphone, Accessibility, Input Monitoring, system audio) to the app's code signing identity,
so the identity must be stable across releases or every user has to re-grant permissions after
each update.

The plan commits to a Developer ID signed and notarized DMG for v1, launch at login through
`SMAppService`, and an explicit decision about the update mechanism (for example Sparkle) rather
than an implicit one.

`tools/package-app` already assembles a local bundle and ad-hoc signs it for development
(ADR 0009). That path is unchanged; this ADR covers the release path only.

## Decision

1. **Distribution form: Developer ID signed, notarized, stapled DMG.** `tools/package-dmg`
   stages the app next to an `/Applications` symlink and writes a compressed read-only image;
   `tools/notarize` signs nested code inside out, notarizes with `notarytool --wait`, staples the
   ticket, and runs `spctl --assess` as the final gate. `make dmg`, `make sign`, `make notarize`
   and `make release` wrap both tools.
2. **Hardened runtime is required.** Signing always passes `--options runtime`; the entitlements
   file stays the single source of truth for the few exceptions the app actually needs.
3. **The signing identity is configurable, never hardcoded.** `SUPERFLOW_SIGN_IDENTITY` and the
   notarytool keychain profile (`SUPERFLOW_NOTARY_PROFILE`, default `superflow-notary`) come from
   the environment. No credentials or team identifiers live in the repository.
4. **Updates: SMAppService for launch at login now; Sparkle deferred.** Ship v1 with launch at
   login via `SMAppService` and a manual "check for updates" that opens the release page. Adding
   an in-app auto-updater means pulling in a third-party framework that needs its own signed
   helper and its own security review, and the plan allows it to be a post-v1 decision. Revisit
   in Phase 9 with the appcast-ed signing key story written down.
5. **Third-party notices ship in-app** (already bundled under
   `App/SuperflowApp/Sources/SuperflowAppCore/Resources/ThirdPartyNotices`), which is a
   prerequisite for the NVIDIA model, S1-mini, Harper, llama.cpp and FluidAudio licenses.

## Consequences

- Release requires a Developer ID Application certificate and a stored notarytool profile; CI on
  GitHub-hosted runners cannot hold those secrets for PRs, so notarization runs on a
  maintainer's machine or a self-hosted runner, never on untrusted pull requests.
- Because the identity is stable, permission grants survive updates.
- Until Sparkle (or an equivalent) is added, users update by downloading a new DMG; the app must
  therefore detect and report a version mismatch rather than assume it is current.
- The DMG is a thin container around the same bundle the smoke test already verifies, so
  `app-smoke` coverage carries over to the release artifact.
