# Git Rules: Multi-Agent Repo

You are not alone in this repo. Other agents work here at the same time, on the same `main`, often in the same working tree. Every rule below exists so your work lands cleanly and never damages theirs.

## The Loop (every task, every time, no batching)

1. `git status`: confirm you're on `main` and the tree is in a normal state.
2. `git diff`: review every change you made. Read it, don't skim it.
3. `git add <path> <path>`: stage only the files you changed, by explicit path.
4. `git diff --cached`: confirm the staged diff is exactly your work and has no secrets.
5. `git commit -m "<6-12 word message>"`
6. `git push`
7. `git status`: confirm clean and in sync.

No change is too small to commit. No "I'll commit these together later."

## Allowed Git Commands

**Write actions (the only three):**
- `git add`
- `git commit`
- `git push`

**Read-only (use freely, only in read-only form):**
`status`, `diff`, `diff --cached`, `log`, `show`, `blame`, `ls-files`, `rev-parse`, `remote -v`, `branch` (list only, no arguments), `config --get`.

**Anything not on this list is forbidden.**

## Forbidden (without explicit human permission)

Forbidden: `checkout`, `switch`, `restore`, `reset`, `revert`, `rebase`, `merge`, `pull`, `fetch`, `stash`, `clean`, `rm`, `mv`, `cherry-pick`, `tag`, `commit --amend`, `push --force`, `push --force-with-lease`, `--no-verify`, branch create/delete/rename, any `git config` write, and any other command that changes the working tree, the index, history, refs, or config beyond add/commit/push.

Why: other agents have uncommitted work in this tree and commits in flight. These commands silently destroy or hide that work. You can't see what you'd be erasing.

**Unlock rule:** the human must explicitly name the command in the current conversation. Permission covers that one command for that one task. It is never standing, inferred, or implied, and "this seemed obviously right" is not permission.

## Shared-Tree Discipline

- **Stage by path, never sweep.** Don't use `git add .`, `git add -A`, or `git commit -a`. Another agent's half-finished files may be sitting in the tree, and sweeping them in commits their unfinished work under your name.
- **If `git status` shows files you didn't touch, leave them alone.** They belong to another agent. Don't stage, commit, format, or "clean up" those files.
- **If `git diff` shows changes in a file you edited that you didn't make,** another agent edited it too. Stage the file only if the whole diff is safe to commit, otherwise stop and report.
- **Push rejected (remote moved)?** Stop. Don't retry in a loop, don't force. Report to the human what happened. You can't pull or merge without permission.

## Stop Conditions (stop and ask, never improvise)

- No repo initialized, or no remote configured. Don't create or guess one.
- Not on `main`, detached HEAD, or a rebase/merge in progress.
- Unmerged paths or conflict markers in the tree.
- A pre-commit hook fails. Fix the cause and make a **new** commit. Never bypass it.
- Anything looking like a secret is about to be staged.
- You're unsure whether a file is yours.

When you stop, say exactly what you saw and what you need. Don't take a workaround.

## Secrets

Never commit `.env*`, API keys, tokens, private keys, or credentials. Check `git diff --cached` for them before every commit. If one slips into the staged diff, stop and flag it. If one was already pushed, tell the human immediately. Don't attempt to rewrite history to hide it.

## Commit Messages

- 6-12 words. Count them.
- Imperative, specific, plain: what changed and where.
- No prefixes (`feat:`, `fix:`), no emoji, no trailing period, no filler like "various" or "some changes".
- If you can't say it in 12 words, the commit is too big. Split it into separate commits, each staged by path.

Bad: `Made some changes to improve the login flow and fix bugs`
Good: `Fix login redirect looping on expired sessions`

## Summary

- Loop: status, diff, add paths, diff --cached, commit, push, status.
- Only write actions: add, commit, push. Everything else read-only.
- Stage explicit paths. Never touch files you didn't change.
- Commit straight to `main`. No branches, PRs, or merges unless the human asks.
- 6-12 word messages.
- Forbidden commands need explicit human permission, per command, per task.
- Surprises mean stop and report, never improvise.