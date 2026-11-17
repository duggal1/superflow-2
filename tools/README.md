# Tools

## stealth-debug

WindowServer sharing-state dump for Clearly stealth. Uses only the public
`CGWindowListCopyWindowInfo(.optionAll)` API — no private APIs, no
Accessibility permission, no GUI.

```sh
# Human-readable table of every window owned by PID:
swift tools/stealth-debug/main.swift --pid <PID>

# JSON (same data), for scripting:
swift tools/stealth-debug/main.swift --pid <PID> --json
```

Each row prints window **number**, **name**, **bounds** (x,y,w,h), **layer**
and **sharingState** (`kCGWindowSharingState`: `0 = none`, `1 = readOnly`,
`2 = readWrite`). Output JSON: `{pid, windowCount, leakCount, ok, windows:[...]}`.

Exit codes:
- `0` — no capturable windows owned by the PID (`ok: true`).
- `1` — at least one window with sharing state `!= none` (a hiding leak). The
  leaking window numbers are printed.
- `2` — bad arguments.

Intended use: point it at the Running Board PID of the Superflow app during a
share to confirm the app owns zero capturable windows. It reports what the
WindowServer says about the public sharing flag; it is **not** proof that a
meeting client respected the flag — see `docs/stealth-compatibility.md` and use
`StealthVerifier` for the capture-based check.

Headless self-test (creates two offscreen probe windows, one `.none` and one
`.readOnly`, never shown on screen; asserts the tool detects exactly one leak
and reports a clean PID as clean):

```sh
zsh tools/stealth-debug/test.sh
# PASS: stealth-debug headless self-test
```

The tool and fixture are compiled to a temp directory by the test; nothing is
installed and no process outside the test is touched.
