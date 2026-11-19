# Progress — 2026-11-19 Superflow binary / pixelated logo task

- Deleted /Applications/Superflow.app and dist/Superflow.app (user: "completely delete the Superflow binary").
- Pixelated brand-mark.svg: rasterized the shipped rendering (evenodd; matches macOS/AppKit) to a
  24x25 cell grid (cell 4.4 viewBox units, >=50% coverage fills a cell), emitted as a single
  <path fill="#f5f5f4"> with the same viewBox (0 0 108.92 110). Kept the single-path format.
- Regenerated AppIcon.appiconset via tools/gen-appicon (10 PNGs + Contents.json). 16px reads as spark.
- Added docs/brand/favicon.png (64x64, blue tile + pixel mark, matches app icon) and
  docs/brand/favicon.ico (16/32/48). The only deployable site in this repo (hex/site) is the
  separate Hex Rust product and /hex/ is gitignored + untracked, so its Hex-branded favicon was
  left alone; Superflow favicon PNGs committed under docs/brand/.
- Assumption: "with add sign in" = build the binary WITH code signing (Superflow Development
  identity, per tools/dev-signing + tools/package-app), not a new sign-in feature. App is
  deliberately local-first ("No account, no cloud, no telemetry.") and there is no Superflow auth
  backend in this repo, so a sign-in feature would be an unrequested product decision.
- 29 local commits were ahead of origin/main from prior work; pushing per user request carries them.
- .proof/ old task files moved to .proof/archive/20261119T153849Z/ (new-task rule); repo tracks .proof.
