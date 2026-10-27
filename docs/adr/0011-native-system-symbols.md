# ADR 0011: Use native system symbols

**Status:** Accepted

## Context

`DESIGN.md` specifies native SF Symbols with hierarchical rendering. `PLAN.md`
section 18.2 still specifies Hugeicons, and the current SVGs are hand-drawn
approximations rather than a licensed Hugeicons export. The design document is
the source of truth for visual decisions.

## Decision

- Render the typed app symbol set with SF Symbols in hierarchical mode.
- Keep SVG resources out of the app bundle.
- Use system symbols for the sidebar and command palette, including standard
  window and menu commands.

## Consequences

- The app uses the system's consistent symbol weight and appearance behavior.
- The old SVG files are not loaded or distributed by the app target.
- `PLAN.md` section 18.2 should be updated when that document is next revised.
