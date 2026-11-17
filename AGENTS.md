<!-- INIT-RULES:START — do not remove this marker. Managed by `init rules`. -->
> [!IMPORTANT]
> **Before doing anything else, read both files in full, and stay aligned with them for the entire task:**
> - `rules.yaml`
> - `git.yaml`
>
> **`git.yaml` applies to every task. No exceptions.**
>
> **`rules.yaml` applies in full to real, complex work:** features, architecture, database/migrations, security, performance, infrastructure, hard debugging, cross-system changes, anything where testing is core. Mandatory there. No skipping.
>
> **Tiny low-risk edits** (typos, copy, trivial styling, small front-end tweaks, small code edits): use `rules.yaml` `quick` mode only: inspect → edit → verify → completion_audit. Skip the plan, tests_first, and independent_review.
<!-- INIT-RULES:END -->

## Project docs: `design.md`, `architecture.md`, `plan.md`

These keep multiple agents consistent. They live in the repo root.

- `design.md`: UI and visual rules (tokens, components, tone).
- `architecture.md`: system structure, data model, boundaries, key decisions.
- `plan.md`: current work, status, who is doing what.

**Full-stack or complex software: these files are required.**
1. Read all three before starting. They are the source of truth.
2. A file is missing? Create it yourself, drafted from the real codebase. Never invent. Then ask the user your questions about the gaps, once, in one batch, BEFORE you start building. Not mid-task.
3. Never overwrite an existing file. Edit it in place. Keep it short and current.
4. Update them in the same commit as the change that made them stale.

**Simple or front-end-only tasks: ignore these files.** Don't create them, don't ask about them.