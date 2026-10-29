# Dashboard, audio and Island alignment

Use all four DESIGN-REPAIR references as UI specifications, with Part 2 superseding Part 1. Preserve native contracts and privacy. Existing dirty Island files are input, not changes to discard.

1. Read references and trace dashboard/audio/Island composition and producers.
2. Connect the frame-driven stage and meter; complete cancellation, no-signal, history and meeting panel data/actions. Remove obsolete dashboard replay plumbing.
3. Run affected package tests, lint and app build/package checks. Inspect rendered native states and packaged symbols. Record actual limitations.
4. Review owned diffs; commit only owned files. Preserve pre-existing edits.

## Refinement requested after native review

Purpose: recover/copy the actual cleaned transcript within two seconds. Header is status; the dark inset is the readable content; Copy is primary, Paste again secondary, metadata quiet. Empty, failed paste, copying, copied, cancelled and reduced-motion states retain working controls.

Tokens: black Island, `Tok.well` (#0F0F0F in the forced dark appearance) for the transcript, existing text/text2 and blue 600. Albert Sans 350, 11/12/13/22 pt scoped roles, tight tracking. Inner padding 12, action gap 8, compact Island buttons 24 high with 12 horizontal and zero extra vertical padding; onboarding Continue 32 high. User explicitly requested the Sapphire border/inner-highlight exception for these primary actions. Artwork uses a 1.08 geometry multiplier with each cell edge snapped to the actual display grid; no raster scaling.

The product-specific idea stays the real voice envelope: live pixels become the frozen cancellation dissolve and the submitting sweep. Preserve the spring-driven silhouette and use quiet state transitions for action acknowledgement. Perform two native screenshot/review passes, then package and launch the actual app.

## Verified result

- Dashboard now composes Recent dictation and Where you dictate; obsolete keycap/replay UI is removed. Inline audio remains the shared WaveTape/ClipPlayer implementation.
- Island uses frame-driven springs, live meter, submitting sweep, frozen cancel dissolve, compact history and real meeting aggregates/actions. Albert Sans scoped sizes 11/12/13/22 use weight 350, tight tracking and native smoothing. Artwork is 8% larger with snapped cell edges.
- Native screenshot pass 1 exposed the Cancelled row's intrinsic-width overflow. Pass 2 confirmed the transcript prefix and full Undo button remain inside both notch/external card layouts. A long-transcript native pixel regression now checks the full button stays inside the content gutter. Snapshot windows render offscreen.
- Passing checks: Island suite (74 before the final overflow correction), final targeted native copy-panel capture and long-cancel regression; DesignSystem 22, UIComponents 32, Dashboard 26, app Island/meeting integration 10; app/helper builds; packager smoke regression; deep code-sign verification. Native screenshots reviewed in light/dark dashboard and notch/external Island states.
- Packaging root cause: `find` did not traverse SwiftPM's `.build/debug` symlink, silently omitting resource bundles. `find -H` plus a symlink-resource packaging regression fixes it. Final signed `dist/Superflow.app` launches and remains running.
- Broader pre-existing failures remain: lint reports SessionEngine/OnboardingViewModel file lengths and DictationKeyPicker raw control/font violations; app composition pipeline-stage expectation fails; four onboarding tests expect the old step sequence. No checks were weakened. Full release gate is not green. No 120 Hz or Bluetooth timing claim is made.
- Preserve the pre-existing Makefile, large design-document edits and deleted audio fixture outside this source commit.
