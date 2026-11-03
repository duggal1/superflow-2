# Git Rules: Multi-Agent Repo

You are not alone in this repo. Other agents are working here right now, on the same codebase, often at the same time. These rules keep everyone's work separate, reviewable, and landed on `main` without anyone stepping on anyone.

**The deal:** work on a branch named for the change, commit and push every single edit as you make it, then PR and merge that branch into `main`. If the branch/PR/merge path is genuinely unavailable, commit straight to `main` instead. Nothing goes uncommitted. Ever.

---

## 0. Preflight (once, at the start of every task)

Run these:

```
git remote -v
gh auth status
git fetch origin
git worktree list
```

- Remote exists, `gh` is authenticated, you can push branches → **Branch Mode** (the default; sections 1-4).
- No `gh`, not authenticated, no permission to push branches, or worktrees unavailable → **Main Mode** (section 5).
- No remote at all → stop and report. Don't create or guess one.

"I didn't feel like making a branch" is not a failed preflight. Main Mode is for when Branch Mode is impossible, not inconvenient.

---

## 1. Branch naming

Name the branch after **what the change is**, never who you are.

- Format: lowercase kebab-case, 2-5 words, `<area>-<change>`. No slashes.
- Good: `auth-fix-expired-session-redirect`, `billing-add-stripe-webhook`, `onboarding-notion-import`
- Bad: `claude-work`, `agent-3`, `sonnet-changes`, `fix-stuff`, `wip`, anything with a timestamp or random ID.
- One change per branch. Unrelated work gets its own branch, not a ride on someone else's.

## 2. Find the branch before you create one

Hundreds of branches is a failure. Before creating anything:

```
git fetch origin
git branch -a
gh pr list --state open
git worktree list
```

- **Same change already has a branch or open PR?** Join it. Use that branch, don't make a sibling.
- **Nothing matches?** Create it.
- A branch is "the same change" only if it's the same feature, bug, or area of work. Similar-sounding is not the same. Don't dump unrelated work onto an existing branch to avoid making a new one.
- Respect branches you join: don't rename them, don't rewrite their history, don't commit unrelated changes to them.

Branches are short-lived. They die at merge (section 4). That's what keeps the count low.

## 3. Work in a worktree, never in the main checkout

Switching branches in a shared working tree rips files out from under every other agent. So nobody switches. Each branch gets its own folder via `git worktree`.

**Create a new branch + worktree:**

```
git worktree add -b <branch> ../worktrees/<branch> origin/main
cd ../worktrees/<branch>
```

**Join an existing remote branch (no worktree for it yet):**

```
git worktree add --track -b <branch> ../worktrees/<branch> origin/<branch>
cd ../worktrees/<branch>
```

**Branch already in `git worktree list`?** Work in that existing folder. Git won't allow the same branch in two worktrees, so agents on the same branch share one folder. Shared-folder discipline (section 6) applies.

All edits happen inside the worktree. The original checkout is not yours to edit in Branch Mode.

---

## 4. The Loop (every change, every time, no batching)

A "change" is **every file you edit, every function you add, modify, or delete, every config tweak.** Finish one, commit it, push it, then start the next. No "I'll commit these together later." No change is too small.

1. `git status`: confirm you're on your branch and the tree is in a normal state.
2. `git diff`: read every line you changed. Don't skim.
3. `git add <path> <path>`: stage only files you changed, by explicit path.
4. `git diff --cached`: confirm the staged diff is exactly your work and has no secrets.
5. `git commit -m "<6-12 word message>"`
6. `git push` (first push of a new branch: `git push -u origin <branch>`)
7. `git status`: confirm clean and in sync.

Deleting a file: delete it from disk, then `git add <path>` to stage the deletion.

**Push rejected?** Your branch moved on the remote (another agent on the same branch pushed). Run `git fetch origin` then `git merge origin/<branch>`, resolve anything in files you touched, commit, push again. If the conflict is in files you didn't touch, or it fails twice, stop and report.

### Finishing: PR and merge

When your task is done and everything is pushed:

1. **Is anyone else still working this branch?** If `git status` in the worktree shows files you didn't touch, someone is. Don't merge. Leave the PR open (open one if needed) and report.
2. Sync with main: `git fetch origin`, then `git merge origin/main`. Resolve conflicts only in files you touched. Conflicts in anything else: stop and report. Commit the merge, `git push`.
3. Open the PR, once. Check `gh pr list --head <branch>` first. If one exists, reuse it.
   ```
   gh pr create --base main --head <branch> --title "<clear title>" --body "<what changed and why>"
   ```
4. Wait for checks: `gh pr checks --watch`. If they fail, fix the cause, make a **new** commit, push, wait again. Never bypass.
5. Merge, keeping the granular commit history:
   ```
   gh pr merge <branch> --merge --delete-branch
   ```
6. Clean up what you created, from the original checkout:
   ```
   git worktree remove ../worktrees/<branch>
   git branch -d <branch>
   git fetch --prune
   ```

If the merge itself is blocked (required review, branch protection, permissions), stop and report with the PR link. Don't push to `main` to get around it.

---

## 5. Main Mode (fallback only)

Only when Preflight says Branch Mode is impossible. Same Loop, same commit discipline, committed straight to `main` in the main checkout.

- Confirm you're on `main` and the tree is normal before every commit.
- **Stage by path, never sweep.** No `git add .`, `git add -A`, or `git commit -a`. Other agents' half-finished files may be sitting in the tree.
- **Push rejected (remote moved)?** Stop. Don't retry in a loop, don't force. Report what happened.
- No branches, no PRs, no merges in this mode.

---

## 6. Shared-folder discipline

Applies to the main checkout in Main Mode and to any worktree that more than one agent is using.

- **`git status` shows files you didn't touch?** They belong to another agent. Don't stage, commit, format, or "clean up" them.
- **`git diff` shows changes in a file you edited that you didn't make?** Another agent edited it too. Stage the file only if the entire diff is safe to commit. Otherwise stop and report.
- **Not sure whether a file is yours?** Stop and ask.

---

## 7. Commands

**Write actions allowed:**

- `git add`, `git commit`, `git push`
- `git fetch`
- `git merge origin/main` and `git merge origin/<your-branch>`, on your own branch only
- `git worktree add` (new worktrees), `git worktree remove` (only ones you created, only when clean)
- `git branch -d <branch>` (only branches you created, only after merge)
- `gh pr create`, `gh pr merge --merge --delete-branch` (only PRs you opened or joined, only per section 4)

**Read-only, use freely:**
`status`, `diff`, `diff --cached`, `log`, `show`, `blame`, `ls-files`, `rev-parse`, `remote -v`, `branch -a`, `worktree list`, `ls-remote`, `config --get`, `gh pr list`, `gh pr view`, `gh pr checks`, `gh auth status`

**Forbidden without explicit human permission:**

`checkout`, `switch`, `restore`, `reset`, `revert`, `rebase`, `pull`, `stash`, `clean`, `rm`, `mv`, `cherry-pick`, `tag`, `commit --amend`, `push --force`, `push --force-with-lease`, `--no-verify`, `branch -D`, `worktree remove --force`, any `git config` write, deleting or renaming branches you didn't create, closing or merging PRs you didn't open, pushing directly to `main` while in Branch Mode, and anything else that rewrites history, refs, or someone else's work.

**Anything not listed above is forbidden.**

**Unlock rule:** the human must explicitly name the command in the current conversation. Permission covers that one command for that one task. It is never standing, inferred, or implied.

---

## 8. Stop conditions (stop and ask, never improvise)

- No remote configured, or no repo initialized.
- Detached HEAD, or a rebase/merge you didn't start is in progress.
- Unmerged paths or conflict markers in files you didn't touch.
- A pre-commit hook fails. Fix the cause and make a **new** commit. Never bypass it.
- PR checks fail and you can't fix the cause from your own changes.
- Merge blocked by protection or permissions.
- Anything that looks like a secret is about to be staged.
- You're unsure whether a file or branch is yours.

When you stop, say exactly what you saw and what you need. No workarounds.

---

## 9. Secrets

Never commit `.env*`, API keys, tokens, private keys, or credentials. Check `git diff --cached` for them before every commit. If one slips into the staged diff, stop and flag it. If one was already pushed, tell the human immediately. Don't attempt to rewrite history to hide it.

---

## 10. Commit messages

- 6-12 words. Count them.
- Imperative, specific, plain: what changed and where.
- No prefixes (`feat:`, `fix:`), no emoji, no trailing period, no filler like "various" or "some changes".
- One change per commit. If you can't say it in 12 words, split it.

Bad: `Made some changes to improve the login flow and fix bugs`
Good: `Fix login redirect looping on expired sessions`

---

## Summary

- Preflight → Branch Mode if possible, Main Mode if not.
- Branch name = the change, never the agent or model. Reuse an existing branch for the same change.
- Own worktree per branch. Never switch branches in a shared folder.
- Every file, function, and config change: status, diff, add paths, diff --cached, commit, push, status. Immediately.
- Done? Merge main in, open one PR, pass checks, merge, delete the branch and worktree.
- Branch Mode blocked by tooling? Commit straight to `main`, same loop, stage by path.
- 6-12 word commit messages. No secrets. Surprises mean stop and report.