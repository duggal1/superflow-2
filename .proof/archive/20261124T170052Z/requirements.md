# Requirements

Source: user message — "revert the Notch front end ... revert the intelligence page ... the model is not outputting anything ... make transcription quality generally high quality ... delete it and rebuild it, open it up ... do not make the icon pixelated."

1. Revert the Notch/Island front end completely to the pre-rewrite state (commit `c5110df`, last commit before the 2026-11-17 Island rewrite), removing every file the rewrite added and restoring every file it changed or deleted.
2. Revert the Intelligence page/panel to the pre-rewrite state (remove the `FeatureIntelligence` package added by the rewrite, restore the old Island intelligence seam and the old Intelligence settings tab).
3. Preserve all backend/audio/storage/transcription work that is not the Notch front end (no regression in dictation pipeline).
4. Fix the broken Notch/dictation backend: a dictation must actually produce and insert text (model output not empty) instead of only appearing in History.
5. Raise transcription/cleanup quality to a generally high standard and verify with the repo's quality tests.
6. Restore the original non-pixelated Superflow logo: `brand-mark.svg` and the AppIcon PNGs as they were before `4dc11d7`; remove the pixelated favicons.
7. Delete the existing Superflow app bundle before rebuilding (no stale `dist/Superflow.app` or `/Applications/Superflow.app`).
8. Rebuild the Superflow app from source in release configuration using the repo's own tooling, signed with the `Superflow Development` identity.
9. Install the rebuilt app into `/Applications` and open it.
10. Fix everything needed for the app to build cleanly and the reverted UI to render and behave correctly (no compile errors, no broken/blank Notch states).
