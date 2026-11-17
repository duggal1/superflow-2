# tools/validate-headless

Headless verification harness for the **Dynamic Island intelligence rebuild**
(`.proof/requirements.md`, 21 requirements). This directory is owned by the
validation agent. It contains only tools, drivers and reports — never production
source.

## Ground rules (from `rules.yaml`)

- **No GUI on the user's screen.** The user is working while these tools run.
  Never `open -a`, never raise/activate a window, never move the real cursor,
  never send global keystrokes. A native app may only be launched by the shell
  caller with `open -g -j` (background, hidden) and driven through the
  Accessibility API or `CGEvent.postToPid` to **its own pid**.
- **Capture only the target app's window** (`screencapture -x -l <windowid>`),
  or render views offscreen in a test host. Screenshots go to
  `.proof/validation/screens/`; never in tracked source dirs.
- **JSON out, nonzero exit on failure.** One job per tool.
- **Aggressive, not smoke.** A green build proves nothing about UI. Every
  state is driven and screenshotted; anything partial is a FAIL.

## Files

```
tools/validate-headless/
├── validate-headless          Python driver: requirements → matrix.md + matrix.json
├── checks/
│   ├── _lib.sh                shared verdict/evidence + real-exercise helpers
│   ├── check-01.sh … check-21.sh   one script per requirement
│   └── integrity-tests.sh     explicit gate: frozen tests, no deleted/weakened test,
│                              lint clean, release build, six focused XCTest suites
├── IslandUIDriver.swift       AX / window / capture / own-pid key probe (Swift)
├── IslandUIDriver             compiled binary
├── window-share-dump.swift    public-CGWindowList inventory for R17 stealth
├── window-share-dump          compiled binary
└── README.md                  this file
```

## Quick start

```bash
# 1. Full matrix (writes .proof/validation/matrix.md + matrix.json)
tools/validate-headless/validate-headless

# 2. Re-run a subset while agents are still editing
tools/validate-headless/validate-headless --only 6,7,10

# 3. Do not fail the process (useful for a report-only pass)
tools/validate-headless/validate-headless --no-fail

# 4. Per-check timeout (default 300s)
VH_TIMEOUT=180 tools/validate-headless/validate-headless
```

Each check prints exactly one line — `<PASS|FAIL|UNVERIFIED>\t<evidence>` — and
exits `0/1/2`. Raw stdout+stderr is archived to
`.proof/validation/logs/check-NN.log`.

## How a requirement is graded

| Verdict | Meaning |
|---------|---------|
| PASS | Exercised the real thing and it held. Evidence is a command + its output, or a screenshot path. |
| FAIL | Exercised and it broke, or the required artefact/behaviour is absent. |
| UNVERIFIED | Could not exercise it: another agent is still editing, a macOS permission is missing, or no driver exists yet. **Never counts as PASS.** |

## Strengthened grading (no PASS on source grep alone)

The original checks emitted PASS on source grep, which violates the status key.
They are now **exercise-backed**:

- `checks/_lib.sh` provides `test_exercise(pkg, filter, label)`: it runs the real
  `swift test` filter and requires `rc=0`, `>0 tests executed`, and `0 failures`
  (a filter matching nothing cannot pass). It also provides `source_only()`,
  which downgrades a pure source observation to `UNVERIFIED`.
- Requirements with real logic (R3, R5–R17) now require the relevant focused
  XCTest suite to actually pass. R4 runs the real `tools/lint-forbidden`.
  R18 runs the compiled `IslandUIDriver frontmost` probe (no focus steal).
  R19 requires real non-empty PNGs in **both** passes, not just prose.
- Stale check paths were fixed: R13's literal `general` case was a false FAIL
  (`normal` is labelled "General Meeting"); R15/R16 grepped deleted
  `Island*` files while the implementation lives in `FeatureIntelligence`.
- `checks/integrity-tests.sh` (called by `check-20.sh`, also runnable standalone)
  is the explicit integrity gate: the two frozen Island tests must be restored
  **byte-for-byte vs git HEAD**, no test file may be deleted or lose any
  `func test`/`XCTAssert` vs HEAD, lint must be clean, the app must compile in
  release, and all six focused packages must pass their real suites.

The independent grader (`.proof/validation/review.md`) FAILs anything partial,
smoke-only, unverified, or weaker than a sibling feature.

## Drivers

### `IslandUIDriver` (Swift, compiled once)

```bash
swiftc -O tools/validate-headless/IslandUIDriver.swift \
       -o tools/validate-headless/IslandUIDriver

# inventory of the target app's windows (needs Screen Recording perm for titles)
tools/validate-headless/IslandUIDriver windows --bundle com.superflow.app

# accessibility tree (needs Accessibility perm)
tools/validate-headless/IslandUIDriver ax --bundle com.superflow.app

# prove no focus steal: frontmost app must NOT be com.superflow.app during tests
tools/validate-headless/IslandUIDriver frontmost

# capture ONLY the Island panel window, off the user's screen
tools/validate-headless/IslandUIDriver capture --window <id> \
  --out "$PWD/.proof/validation/screens/island.png"

# post a synthetic key to the app's OWN pid (needs Accessibility perm)
tools/validate-headless/IslandUIDriver postkey --pid <pid> --code 61 --down
```

If the app is not running, the shell caller launches it **hidden** first:

```bash
open -g -j dist/Superflow.app     # background + hidden; never 'open -a'
```

The driver never launches, focuses, or raises anything, and never posts a
global event.

### `window-share-dump` (R17)

Public `CGWindowListCopyWindowInfo` inventory of the app's windows. Note:
`sharingType` is **not** exposed by any public WindowServer API; the dump
records the window inventory the SCK positive-control verifier operates on.
The in-app DEBUG invariant and the verifier are the actual stealth proof.

```bash
tools/validate-headless/window-share-dump --bundle com.superflow.app \
  --out "$PWD/.proof/validation/windows.json"
```

### Headless view screenshots (no app launch at all)

The Island snapshot XCTest cases render every state into an offscreen host
window at `(-10000, -10000)` and write PNGs when an env var is set. This is the
preferred screenshot path — it never touches the user's screen:

```bash
ISLAND_SNAPSHOT_DIR="$PWD/.proof/validation/screens/pass1" \
IDLE_LAMP_SNAPSHOT_DIR="$PWD/.proof/validation/screens/pass1" \
  swift test --package-path Packages/L3-Features/FeatureIsland
```

## Two-pass screenshot review

1. **Pass 1** — generate screenshots into `screens/pass1/`, `Read` every PNG,
   judge it against `DESIGN.md §8.18`, `DESIGN-RULES.MD` and the requirement,
   and record what is weak. Fixes are requested through
   `.proof/validation/report.md`; the validation agent never edits source.
2. **Pass 2** — re-generate into `screens/pass2/` (after fixes land or as a
   fresh-eyes pass), `Read` every PNG again, and record what changed and what
   still fails. Log both passes in `.proof/validation/screenshot-review.md`.

## Permissions that can block runtime checks

- **Screen Recording** — window titles / `screencapture -l` / SCK verifier.
- **Accessibility** — AX tree and `CGEvent.postToPid` to the app's own pid.
- **Input Monitoring** — the app's own global listen-only hotkey tap (R7/R9).

When one is missing, a check reports `UNVERIFIED` with the exact permission
name; it is not silently treated as a pass.
