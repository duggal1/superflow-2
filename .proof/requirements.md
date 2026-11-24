# Requirements

Source: user message — "I want you to delete the current binary, rebuild it, and open it up for me. Move it to the application folder with add sign-in key"

Interpretation: "sign-in key" = the stable local code-signing identity (`Superflow Development`) that
`tools/dev-signing` manages and `tools/package-app` uses. The user wants the installed app replaced
by a fresh, signed rebuild placed in `/Applications` and then launched.

1. Delete the current binary before rebuilding: remove `/Applications/Superflow.app` and any stale
   `dist/Superflow.app` so no old bundle survives.
2. Add/ensure the local code-signing identity ("Superflow Development") exists and is usable, and
   use it to sign the rebuild (the "sign-in key").
3. Rebuild the app from current source in release configuration with the repo's own tooling
   (`make app` / `tools/package-app`), with a real app executable, resource bundles, helper, and dylibs.
4. Verify the rebuilt binary headlessly: `codesign --verify --deep --strict`, signature authority,
   audio-input entitlement, valid Info.plist and executable.
5. Move/install the rebuilt app to `/Applications/Superflow.app` (replace the deleted one).
6. Open the installed app for the user.
7. Completion audit: two consecutive full passes with zero FAIL/UNVERIFIED.
