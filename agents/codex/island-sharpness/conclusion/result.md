# Island design integration

The existing implementation already contained the supplied scenes and most visuals. The missing seams were host focus, hit testing with preferences, long-text constraints, and passive notice scheduling.

## Result

- Shell, wing layout and host use one `model.box`. The host tests the actual path, so transparent corners and a hidden external idle state stay click-through.
- Live and hinted wings include their flares when clamped to the 520 × 360 canvas. A visible idle lamp extends 5 pt below hardware rather than being drawn behind it.
- History keeps close/copy controls in view with long transcripts, and scrolls when keyboard selection or expansion changes.
- History and the expanded meeting panel become key. Real Return copies cleaned text; real Escape dismisses history and collapses meetings. Paste failures remain nonactivating.
- The model no longer manufactures word milestones. Passive notices queue behind live work and cards, with a four-item bound, 600 ms gap and 120 s expiry. Existing explicit refusal feedback still works.
- Collapsing a meeting does not replay introductory hints. Hiding live text clears the retained partial.

## Evidence

`swift test --package-path Packages/L3-Features/FeatureIsland` passed 68 tests. `python3 tools/verify-island` builds actual source symlinks with production UI dependencies and additionally exercises three NSPanel host tests. For previews, set `ISLAND_SNAPSHOT_DIR=/tmp/superflow-island-preview` before that command. Native Retina snapshots cover nine states on wide-notch and external geometries. The first layout/focus change was pushed as 44eb16b.

At the outset the full dependency graph failed in another worker's in-flight TextCleanup/ListPlanner code. The isolated package allowed useful verification without editing that work. After those changes settled, the normal feature package passed too. The isolated harness excludes unused speech-engine package dependencies; it does not certify the complete application or audio pipeline.

`tools/lint-forbidden` reported four unrelated onboarding violations (file length, raw Button and font rules). Leave those edits with their owner.

## Lessons and remaining limits

ImageRenderer omits native controls and ScrollView contents and can trigger FocusState warnings. Inspect NSHostingView captures for this feature; allocate the bitmap at 2× explicitly. A transient `copiedID` is a timing-sensitive keyboard assertion under load; assert the clipboard's cleaned text instead.

DESIGN.md is ignored locally. Its §0.11 and §8.18 were updated without forcing it into source control. Other agents had substantial changes in the shared tree; they were not staged here. Live diarization accuracy and real 16-inch hardware behavior remain outside these synthetic geometry/render checks.
