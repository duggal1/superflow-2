# Requirements — clean sweep (2026-11-18)

Source: user message verbatim intent —
"I want you to check using Git: 1. If there is uncommitted work, I want you to commit all the work and make the tree clean and push everything to me. 2. I want you to check AI agent's work for the latest that's happening right now (30 minutes ago or what?). See if all the tests are green and do everything. I want you to launch three sub-agents for this clean sweep work"

1. Detect all uncommitted work (modified tracked files, untracked source/tests/evidence) in /Users/harshitduggal/workspace/superflow.
2. Commit ALL of that work with 6-12 word messages, no secrets, no build/junk artifacts, leaving `git status` clean.
3. Push everything to origin so it lands on main (multi-agent mode: agent branch + PR merged to main with a merge commit).
4. Pull/merge main before pushing; never rebase a pushed branch; never restore/reset/force-push.
5. Investigate the latest AI agent work (~30 minutes ago): what changed, when, which agent/evidence dir, and whether it is complete or in-progress.
6. Verify ALL tests are green: `make verify` (deps-check, lint-forbidden, every SwiftPM test package, release build). Fix or explicitly flag any failure; no weakened/deleted tests.
7. Launch exactly three sub-agents for the clean sweep: git-work analyst, test runner, uncommitted-diff reviewer.
8. Completion audit: two consecutive full passes re-running checks, zero FAIL/UNVERIFIED; report DONE or BLOCKED with one line of evidence per requirement.

## Constraints carried from rules.yaml / git.yaml
- Headless testing only; never launch a GUI window, browser, or `make run`/`open`.
- Never commit secrets, .env, credentials, or tokens.
- Never use git restore, git reset, or force push without explicit permission.
- Do not edit frozen tests or weaken tests to make them pass.
- Sub-agents are read-only: no source edits, no git mutations.

## Assumptions (logged, not asked)
- Multi-agent git mode applies: multiple OpenCode sessions are active and the user explicitly asked for three sub-agents. Only this agent performs git writes, on branch `agent/clean-sweep`.
- The untracked `.proof/*/` directories are agent evidence and are part of "all the work"; they are committed rather than discarded.
- Only the two stale state files were archived (`.proof/archive/20261118T174334Z/`); evidence directories stay in place to avoid breaking their internal references.

## Added by the user's follow-up message (same task, new requirements)
9. Commit ALL uncommitted work produced by all agents and push it to `main` (multi-mode branch + PR merge so it lands on main).
10. Spawn at least five specialized sub-agents, plus a sixth dedicated cleanup sub-agent.
11. Sub-agent A — performance/footprint: answer whether the app is lightweight on memory and disk space, or heavy, with measured evidence.
12. Sub-agent B — transcription speed: answer whether transcription is "extremely hyper-ultra-fast" or not, with measured evidence.
13. Sub-agent C — transcription quality: focus on S1-mini and how important/correct transcription quality is.
14. Sub-agent D — Intelligence page: test whether it actually works.
15. Sub-agent E — extreme reliability, code quality, code review, brutal testing, and more; includes diagnosing the 1 pre-existing AudioCpp `StreamingProfileTests` failure.
16. Sub-agent F — cleanup: delete dead code, unused assets, unused `.proof` data, and bloat; user explicitly authorized deletion. Must verify before deleting and work in an isolated worktree/branch.
