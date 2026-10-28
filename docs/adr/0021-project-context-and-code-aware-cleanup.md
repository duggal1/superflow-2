# ADR 0021: Injected project scope and code-aware text cleanup

Status: Accepted

## Context

Dictionary and cleanup improvements were being asked to handle coding
dictation: spoken filenames, extensions, and project paths. The safe way to do
that needs a filesystem boundary, but the text stack runs on every keystroke and
must never walk a disk, guess a project from the frontmost app, or invent a path.

The deterministic tier also needed two mechanical gaps closed: repeated words
("the the") and code-shaped line formatting that was capitalizing commands,
splitting filenames at the dot, and rewriting fenced blocks.

## Decision

### 1. Project scope is injected, never discovered

`SuperflowKernel.ProjectContext` is the only filesystem scope a text stage sees:

- `root` is an explicitly selected directory, canonicalized once at injection.
- `paths` is a project-relative index bounded by `ProjectContext.pathLimit`
  (4,096) and `pathLengthLimit` (512 bytes).
- `normalizedRelative` rejects absolute paths, `..`, NUL, empty components and
  oversized paths; `contains(relative:)` is lexical and performs no disk access.
- `isCoding` upgrades `TextContext.cleanupContext` to `"coding"`.
- `approvedByUser` records that a person chose the scope.

`SuperflowProjectIndex` (L1) is the only component that walks a tree. It runs on
explicit project open/refresh, prunes hidden files, symlinks and generated
directories, caps depth, and returns a `ProjectContext`. Cleanup only reads the
already-bounded index.

### 2. Stage order

`TextPipelineBuilder` now emits:

```
commands, shortcuts, disfluency, numbers, [codeSpeak], lexicon,
codeAware, cleanup, numbers.assert, lexicon.assert, grammar, lineformat
```

- `TextDisfluency` runs before any model. It only collapses duplicate runs and
  optionally removes standalone pure fillers; contextual fillers stay with the
  cleanup model. A line that would become empty is returned as dictated.
- `TextCodeAware` runs after the lexicon and before cleanup. It normalizes
  spoken extensions and filenames and resolves a phrase to a project path only
  when the bounded index has exactly one match. Ambiguous, common, protected or
  out-of-root spans are left untouched. Every emitted literal is protected.
- `TextCodeSpeak` remains opt-in and still owns identifiers, symbols, flags and
  spoken slashes.

### 3. Cleanup and formatting

- `CleanupService` receives the draft's protected spans and uses them when a
  retry split must avoid a protected token.
- The model control line uses `TextContext.cleanupContext` and a deterministic
  list detector. Only strong cues (two or more bullet/numbered lines, an explicit
  intro cue, or three ordered ordinals) upgrade `prose` to `list`; an explicit
  user structure is never overridden.
- `TextLineFormat` splits fenced code out before formatting and masks inline
  code, paths and filenames while formatting. Code is restored byte-for-byte.
  An unclosed fence stays code. List marker spacing is normalized without
  inventing or renumbering items.

### 4. Bounds and failure behavior

- Every deterministic stage returns its input unchanged plus a diagnostic when
  it cannot improve the text.
- `SessionCleanupCoordinator` gives interactive rows priority over background
  rows while keeping the queue bounded.
- Project propagation lives on `SessionEngine` and `MeetingEngine`; nil means
  filename-only cleanup and no path resolution.

## Consequences

- No stage performs a filesystem walk during cleanup. A missing project scope
  degrades safely to prose.
- Spoken filenames work without any project; path resolution requires an
  explicitly indexed project.
- Code in dictation survives capitalization, punctuation spacing and line
  wrapping.
- A wrong index cannot leak content outside the approved root, and symlinks are
  never followed by the indexer.

## Tests

Unit and property tests cover `ProjectContext` bounds and traversal rejection,
the disfluency duplicate threshold, code-aware filename/path precision,
`ProjectIndexer` pruning and limits, cleanup list cues and protected retry
splits, and fenced/inline code formatting. Golden fixtures exercise real-style
dictation for disfluency, code-aware cleanup, line formatting and the full
pipeline stage order.
