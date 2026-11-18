# Agent 4 requirements — Knowledge front end + History design

Source: parent session task, read word by word. Frozen; add only, never loosen.

1. Read in full: `CLAUDE.md`, `AGENTS.md`, `rules.yaml`, `git.yaml`, `DESIGN.md` (§0.4, §4, §5, §7, §8 esp. EmptyState/History/Segmented), `DESIGN-RULES.MD`, current `KnowledgeView.swift`.
2. Delete and rebuild `KnowledgeView.swift` as a designed knowledge console, not a generic form wall.
3. Use only shared components: `Card`, `Segmented`, `SearchField`, `EmptyState` (pixel full stop), `AppButton`, `Badge` for status, `DialogHost` for add/edit. No `.sheet`/`.alert`/`.popover`, no raw controls in feature code.
4. Structure: one purpose per section, one accent, 4 pt grid, one left edge, selectable text, keyboard/VoiceOver labels.
5. Fix the owner's named defects: text breaking down vertically; broken line clamping/truncation; inconsistent "and more" affordances ("three rewrite, four polish, text break down vertically, line clamping is break, unmatch with and more").
6. Rows clamp predictably and never cut controls (fixed control column; edge fade, not hard clip).
7. History: row text leads with the transcript, not a date.
8. History: no broken vertical breaking; one-line clamp with edge fade; meta row intact; controls never clipped; in-place expansion correct.
9. History follows `DESIGN.md` §0.4 and §8.10 exactly (56 pt rows, icon 20, gap 12, 13/500 transcript, 12/350 meta with relative time + tabular word count, no speech rows dimmed with no count, detail order and header geometry, 32 leading inset / 32 horizontal detail padding / 48 bottom).
10. Write exact view-model API needed by the front end to `.proof/knowledge-front/expected-backend-api.md`; read `.proof/knowledge-back/provided-backend-api.md` if it appears and adapt.
11. Do not edit Dictionary/Shortcuts packages or the SQLite store (Agent 5 owns them). Do not edit anything outside owned files.
12. Verify: `tools/lint-forbidden` clean; `swift build --package-path App/SuperflowApp --configuration release` green; `KnowledgeNoticeRouterTests` + FeatureHistory tests run, counts reported.
13. Render headless screenshots of knowledge/history if feasible; otherwise explain why in the report.
14. Kill any command hanging > 10 minutes. Never weaken tests.
15. Deliver `.proof/knowledge-front/report.md`: before/after structure, contract file, test/lint/build evidence, honest gaps. STATUS DONE only if all green.
