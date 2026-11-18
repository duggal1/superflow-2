# Agent 4 report — Knowledge front end + History design

**STATUS: DONE.** All required lint, build and tests are green in two consecutive passes with no
code changes between them. Two honest gaps remain (no rendered screenshot; partial text selection
inside clickable rows) — both explained in §5.

---

## 1. Before / after structure

### Knowledge — before (form wall)

- `Page` → `ListControls` → an unbroken run of groups: Terms card, Corrections card, Shortcuts
  card, Learning card, playground card. No overview, no state readout, no consistent overflow.
- `EntryRow` used `PixelChip` + an unbounded result `Text` with `.lineLimit(1)` and no width cap;
  long triggers/results could push the row, stack words vertically, or hard-clip the text.
- Learning rows put `"heard → canonical"` in an HStack with `Spacer(minLength: 12)` and three
  buttons; a long candidate squeezed or clipped the controls.
- Status appeared only as an occasional `Badge("Inline")`.

### Knowledge — after (knowledge console)

`Page(title: "Knowledge")` with one purpose per section, one accent (the `Add` primary in
`ListControls`), one left edge, 4 pt grid, shared components only:

1. **Controls** — `Segmented` `All | Dictionary | Shortcuts | Learned`, `SearchField`, `ActionMenu`,
   one primary `Add`; ⌘N / ⌘F and JSON import/export preserved.
2. **Ledger card** — `Card` + `SectionHeader("Knowledge base")` + three `Metric`s
   (Terms / Shortcuts / Suggestions). Counts come from the whole library, not the filter, so they
   do not jitter during search. This is the page's one live readout.
3. **Rule cards** — one card per kind, `SectionHeader` + one-line `KnowledgeRow`s. `All` previews
   four rows per kind; a focused scope shows all. Overflow is **one** `+N more` `.link` button in
   every group — no mixed ellipses / "Show all" / "and more" phrasings. Search disables the preview
   so a match is never hidden behind the link.
4. **Learning card** — the two existing toggles, the local-only note, then inbox rows.
   `LearningRow` gives candidate text a flexible `minWidth: 0` column with a 24 pt edge fade and a
   fixed, `layoutPriority(1)` control cluster (Confirm/Reject or `Badge("Added")`/Undo).
5. **Try it** — `DictionaryPlayground` stays as its own section, running the real lexicon stage.
6. **Empty** — `EmptyState` (pixel full stop) with a next-action sentence, shown only when active
   scopes have no visible content and neither store is loading.

| Owner defect | Fix |
|---|---|
| text breaks down vertically | `.lineLimit(1)` + `frame(minWidth: 0, maxWidth: .infinity)` on every row text; trigger is a fixed 168 pt column. Nothing expands to a new line. |
| line clamping is break | Hard truncation → `.modifier(TextFade(length: 12/24))`, an alpha mask on the tail: text dissolves instead of clipping or growing an ellipsis. |
| inconsistent "and more" | One `+N more` `.link` button, one label form, one placement (inside the group card), on all three rule kinds; disabled during search. |
| controls clipped | Controls use `.fixedSize(horizontal: true, vertical: false)` + `.layoutPriority(1)`; flexible text shrinks first. Edit/Delete remain in `DialogHost` / context menu. |

### History — before → after

- Row text leads with the transcript via `title(for:)` = preview → session title → "No speech";
  the date is meta only (`Humanize.when` in `TimelineView(.everyMinute)`) with a tabular word count
  and no count on no-speech rows.
- Transcript is one line, `.lineLimit(1)`, flexible frame, 24 pt `TextFade` — no vertical stacking,
  no hard cut. The meta row keeps its own 16 pt frame and stays intact.
- Detail empty state is `EmptyState(..., density: .pane)` (11-cell pixel stop + 15/500 title + a
  next-action sentence) per §8.10; previously it was a bare `PixelStop` + title.
- Detail header: app name clamps and fades; Copy/Delete are right-aligned **4 pt apart**, fixed-size,
  `.layoutPriority(1)`, with the existing `-8` pull-out so the glyph edge equals pane right − 32.
- `DiffTranscript` keeps `.id(session.id)` and `$model.showRaw`, so the Cleaned/Raw in-place
  expansion belongs to the selected session and cannot leak into the next one.
- Removed the dead `CopyButton` (unused duplicate of the shared `RowCopyButton`).
- Kept: 56 pt rows, 20 pt icon, 12 pt gap, 13/500 transcript, 12/350 meta, detail order
  (header → audio → Cleaned/Raw), 32 pt pane inset, 32/48 detail padding, no `DateFormatter`,
  no raw controls.

## 2. Peer contract

- Published first: `.proof/knowledge-front/expected-backend-api.md`.
- Read in full on arrival: `.proof/knowledge-back/provided-backend-api.md`.
- Agent 5 preserved every signature I consume (`visibleEntries`, `entries`, `isLoading`, `query`,
  `toast`, `load/save/delete/exportData/importData`, `candidates/confirm/reject/undo`,
  `setOnApplied`). No front-end source change was needed; the only contract edit corrected
  `setOnApplied` to its real actor-isolated synchronous signature. I did not adopt the additive
  plain-text import/export or `search(_:)` — out of scope.

## 3. Verification evidence

Two clean passes, no code changes between them. All commands ran one at a time under
`/tmp/superflow-build-lock` with `--jobs 1` and a hard watchdog; load stayed ≤ 25 and falling.

| Check | First pass | Final pass |
|---|---|---|
| `tools/lint-forbidden` | `Forbidden-pattern lint passed.` | `lint=0` |
| `swift build --package-path App/SuperflowApp --configuration release --jobs 1` | `BUILD_EXIT=0`, `Build complete! (22.19 sec)` | `build=0`, `Build complete! (135.36 sec)` |
| `swift test --package-path App/SuperflowApp --filter KnowledgeNoticeRouterTests --jobs 1` | `TEST_EXIT=0`, **1 test / 0 failures** | `router=0`, **1 test / 0 failures** |
| `swift test --package-path Packages/L3-Features/FeatureHistory --jobs 1` | `TEST_EXIT=0`, **8 tests / 0 failures** | `history=0`, **8 tests / 0 failures** |
| `git diff --check` on owned files | clean | clean |

Test counts: `KnowledgeNoticeRouterTests` **1/1**, `FeatureHistoryTests` **8/8**. No test was
edited, weakened or deleted; `HistoryViewModelTests.swift` and `KnowledgeNoticeRouterTests.swift`
are byte-for-byte untouched. Logs: `build-release*.log`, `final-*.log`, `test-*.log` in this folder.

One compile error was found and fixed during verification: `KnowledgeView.swift` used `IconView`
without importing `SuperflowIcons`; the subsequent release build and all tests are green.

`pass2.log` records a transient pass where the disk filled (`error: other(28)` / ENOSPC) and a
grep-based status line masked the test exit codes. It is **not** a pass; the issue cleared and the
final pass above uses explicit exit codes. `test-featurehistory-retry.log` is the successful retry.

## 4. Files changed (only owned paths)

- `App/SuperflowApp/Sources/SuperflowAppCore/Windowing/KnowledgeView.swift` — full rebuild (389 lines).
- `Packages/L3-Features/FeatureHistory/Sources/SuperflowFeatureHistory/HistoryView.swift` — design fixes (268 lines).
- `.proof/knowledge-front/{expected-backend-api.md,requirements.md,progress.md,report.md}` + verification logs.

`KnowledgeNoticeRouter.swift` was reviewed and needed no change; no commit/push/PR per instruction.

## 5. Honest gaps

1. **No rendered screenshots.** A native SwiftUI window cannot be truly headless (rules.yaml
   `macos_native`); capturing it requires launching the app with `open -g -j`, Screen Recording and
   Accessibility permissions, driving the Accessibility API and capturing only that window id.
   A pixel-level render harness would need a new test/driver file outside my sole ownership. The
   numeric design constants are asserted by construction (tokens/frames/pixelAudit) and by lint,
   not by a screenshot pass.
2. **Selectable text in rows is partial.** `Text` inside `RowButton` carries `.textSelection(.enabled)`,
   but a Button may capture clicks; full selectable text is available in the edit dialogs and the
   playground. A non-clickable row would fix it but would break the shared "row is wholly clickable"
   pattern, so I kept the pattern.
3. **`DiffTranscript`'s `+N more` line lives in UIComponents** (`DiffTranscript.swift:119`) as a plain
   caption, outside my ownership; my views use one consistent affordance, but that shared component
   remains a visual mismatch to flag to its owner.
4. Pixel-grid 2× crops, dark/light and 400% zoom were not captured (same reason as #1).
