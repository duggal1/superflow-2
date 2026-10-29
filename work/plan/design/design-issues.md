# Design issues

- Purpose: make the app's navigation, titles, settings controls and past meetings readable and consistent.
- Hierarchy: page title, task controls, content; past meetings expand in the list and give transcripts the full measure.
- States: empty, search empty, loading, failure, selected, hover, pressed, focus, disabled, copy success and failure; respect Reduce Motion.
- Tokens: existing Tok surfaces and Blue 600; existing Space, Radius and control-height tokens; title roles in the shared typography system. Pixel switch: 9 × 5 cells, 4 pt pitch, 3 pt cells, 35 × 19 pt artwork, 32 pt minimum target height, 200 ms state transition.
- Novel idea: the toggle surface itself fills with the same pixel language as the download progress, and the meeting timeline remains attached to its expanding row.
- Sequence: establish shared controls and icons; apply typography after checking font rights; implement meetings behavior; inspect affected screens twice and run affected package tests and lint. Preserve unrelated work in the shared tree.
- Font: bundled SerifVinci.otf and source woff2 identify a trial face and contain no license; permission to ship in a desktop app is unverified.
