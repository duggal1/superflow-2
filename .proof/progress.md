# Plan

Goal: delete the installed Superflow binary, ensure the local signing identity is present, rebuild a
signed release app, verify it, install to /Applications, and open it.

Non-goals: no source-code feature changes, no reverting prior work, no notarization/Developer ID
release, no touching model files or user data.

Invariants:
- User explicitly authorized deleting the current binary; no other files are deleted.
- Signing uses the stable `Superflow Development` identity so TCC grants survive rebuilds.
- Verification is headless; the app is only opened at the end, as explicitly requested.
- Git: pull before start (done, already up to date); no secrets in commits.

Steps:
1. Ensure signing identity (`tools/dev-signing`) — verify command: `security find-identity -v -p codesigning`.
2. Delete current binary (`/Applications/Superflow.app`, stale `dist/Superflow.app`) — verify: `ls` shows none.
3. Rebuild release with `SUPERFLOW_SIGN_IDENTITY="Superflow Development" make app` — verify: build exits 0, dist/Superflow.app exists.
4. Verify signature + structure headlessly — verify: `codesign --verify --deep --strict` + entitlement check.
5. Install to `/Applications/Superflow.app` — verify: `codesign -dvv` on installed copy shows the identity.
6. Open installed app — verify: process is running.
7. Completion audit (two passes) and report.

Progress:
- Previous proof archived to `.proof/archive/20261124T170052Z/`.
- Preflight: git clean/up to date; `/Applications/Superflow.app` present and signed with `Superflow Development`;
  no `dist/Superflow.app`; no running Superflow; identity already exists; macOS 27.2 / Xcode 27.2.
- Step 1 DONE: `./tools/dev-signing` confirmed identity "Superflow Development" (9CCF4387...), 1 valid identity.
- Step 2 DONE: deleted `/Applications/Superflow.app` and stale `dist/Superflow.app`; both absent afterwards.
- Step 3 DONE: `SUPERFLOW_SIGN_IDENTITY="Superflow Development" make app` exit 0, 264s app + 27s helper release
  builds; packager output "identity: Superflow Development" (evidence: .proof/build.log).
- Step 4 DONE: headless verification PASS — plutil OK, arm64 Mach-O, helper + dylibs nested,
  `codesign --verify --deep --strict` PASS, audio-input entitlement PASS, helper verify PASS
  (evidence: .proof/verify.log).
- Step 5 DONE: `mv dist/Superflow.app /Applications/Superflow.app`; installed copy signed by
  "Superflow Development", deep-strict verify PASS, entitlement PASS; no bundle left in dist/.
- Step 6 DONE: `open /Applications/Superflow.app`; process 3098 running from installed path; Accessibility
  reports 1 window.
- Next: independent review + second completion-audit pass.
