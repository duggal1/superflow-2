# Native UI reference pass

Implement the supplied reference in order, adapting to current Swift packages and repository protocols. Latest rules supersede earlier Sapphire/glass styling: solid menus, flat primary buttons, compact row controls and an 8 pt submitting scanner.

Structure: shared menus anchor to the actual trigger, expose accessible enabled/destructive/checked items, and support arrows/Return/Escape. Dashboard shows five useful dictations, keeps failed/cancelled rows recoverable, and shares inline playback. Dialogs cover the whole window with bounded fields. Past meetings remains a repository-backed list/reading pane with speaker timelines and working rename/export/delete/undo. Settings reuses shared dropdowns and tick sliders.

Tokens: existing bg/surface/controlHover/controlPressed/text/text2/statusBad/blue ramp; menu rows 32, inset 4, gaps 8, radius 12; dashboard rows 48, app icons 16, action glyphs 12 in 28 targets; dialog actions 32, editor 128; meeting list 320, rows 64, speaker column 120; slider track 280 plus gap 16 and readout 64. No decorative borders, shadows or menu glass. Pixel drawing snaps to device pixels. Motion is state-driven and Reduce Motion stays complete.

1. Replace menu model/panel/triggers, migrate all callers, and test metrics, placement and keyboard behavior.
2. Update recent dictation filtering/retry/controls and scanner. Add behavioral coverage.
3. Update dialogs/fields/segmented controls, disabled primary treatment, settings marks and spring tick slider.
4. Rebuild past meetings over existing repository/engine types, preserving live capture and implementing actions end to end.
5. Native screenshot passes in both appearances; affected tests; required lint/full verification; package/sign/launch. Report unavailable Instruments evidence and unrelated baseline failures honestly.

Working-tree baseline includes audio-enhancement work in AppEnvironment, Kernel/Ports, AudioCapture, engines and manifests, plus existing DESIGN/Makefile/audio-fixture edits. Preserve those changes; do not stage them with UI work. A prior push was rejected because remote main advanced; do not pull, force or merge.
