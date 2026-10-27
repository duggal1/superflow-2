# Runbook: release build (sign, notarize, DMG)

One-time setup on the release machine:

1. Install a **Developer ID Application** certificate in the login keychain.
2. Store notarytool credentials once:

   ```bash
   xcrun notarytool store-credentials superflow-notary \
       --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
   ```

## Cut a release

```bash
export SUPERFLOW_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export SUPERFLOW_NOTARY_PROFILE=superflow-notary   # default

make verify          # build, tests, dependency and forbidden-pattern lint must be green
make release         # app -> dmg -> sign + notarize + staple
```

`make release` runs `tools/package-app`, `tools/package-dmg` and `tools/notarize`, which ends by
running `codesign --verify --deep --strict` and `spctl --assess --type execute` on the bundle.

## Verify the artifact on a clean Mac

1. Mount `dist/Superflow.dmg` and drag Superflow into Applications.
2. Launch it and confirm no Gatekeeper warning (this proves the staple worked).
3. Grant microphone, Accessibility and Input Monitoring, then dictate once.
4. Quit, relaunch, and confirm the permissions are still granted (this proves the signing
   identity is stable, which is the whole reason the identity is pinned).

## Troubleshooting

- **`spctl: rejected`** — the ticket was not stapled, or the app was modified after notarizing.
  Re-run `make release` and do not touch the bundle afterwards.
- **`notarytool: Invalid credentials`** — the keychain profile is missing or the app-specific
  password was rotated; re-run `store-credentials`.
- **Notarization succeeds but launch fails** — a nested helper or framework was left unsigned.
  `tools/notarize` signs inside out; if a new nested binary was added, confirm it is matched by
  the `find` in that script.
- **Permissions reset after an update** — the signing identity changed. Releases must always use
  the same Developer ID; ad-hoc signing (`make app`) is for local development only.
