# Requirements

Source: user message — "delete the current Superflow binary, rebuild the binary, and open it up ... Move it to application folder with add sign-in key, whatever."

1. Delete the current Superflow binary/app before rebuilding (no stale app left at `dist/Superflow.app` or `/Applications/Superflow.app`).
2. Rebuild the Superflow app from source in release configuration using the repo's own build tooling (`make app` / `tools/package-app`).
3. Sign the rebuilt app with a code-signing key so TCC grants stay stable across rebuilds (`Superflow Development` identity in the login keychain).
4. Install/move the rebuilt signed `Superflow.app` into `/Applications`.
5. Open/launch the installed `/Applications/Superflow.app`.
6. Verify every step against the real artifacts: deletion, successful build, valid signature with the expected identity, presence in `/Applications`, and a running process after launch.
