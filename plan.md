# CI failure recovery plan

Root causes: the composition test expects an obsolete stage list; SwiftUI history key handlers
depend on transient view focus even though AppKit has already made the nonactivating panel key.

Files:
- AppCompositionTests: assert the current, explicit structure stage.
- IslandModel and IslandModel+Live: keep selected history index in observable model.
- IslandHistory: render selection from the model, remove focus-dependent key handlers.
- IslandPanelController: handle history Return/arrows/Escape at the AppKit key window.
- IslandPanelControllerTests: verify keyboard selection, copy and dismiss from synthetic key events.

Verification: GitHub Actions Swift 6.4 on Xcode 27, including full `make verify`.
No ASR default, prompt, microphone, or transcript privacy changes.
