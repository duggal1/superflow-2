#!/usr/bin/env bash
# R21: commit/push per git.yaml (6-12 word messages); open a PR and merge/push to main.
# The owner explicitly directed: create the PR, merge every agent's work, and push
# it to main immediately. So a MERGED PR whose merge commit is on main now PASSES;
# an OPEN PR is also accepted. A stale agent branch with no PR at all is a FAIL.
source "$(dirname "$0")/_lib.sh"
cd "$ROOT" || unverified "cannot cd to repo root"
branch=$(git branch --show-current 2>/dev/null)
commits=$(git log -8 --pretty='%h|%s' 2>/dev/null)
agentbranches=$(git branch -a 2>/dev/null | grep 'agent/' | wc -l | tr -d ' ')

openpr=$(gh pr list --state open --json number,title,headRefName 2>/dev/null || echo "")
mergedpr=$(gh pr list --state merged --limit 5 --json number,title,state,mergedAt 2>/dev/null || echo "")
mergecommit=$(git log -1 --pretty='%s' 2>/dev/null)

# Local main must equal origin/main: the merge is pushed, not just local.
aheadbehind=$(git rev-list --left-right --count origin/main...HEAD 2>/dev/null | tr -d ' ')
pushed=0
[ "$aheadbehind" = "0	0" ] && pushed=1

if [ -n "$openpr" ] && [ "$openpr" != "[]" ]; then
  pass "open PR found: $(printf '%s' "$openpr" | cut -c1-160); branch=$branch; main synced=$pushed; commits: $(printf '%s' "$commits" | tr '\n' ';' | cut -c1-140)"
elif [ -n "$mergedpr" ] && [ "$mergedpr" != "[]" ] && [ "$pushed" -eq 1 ]; then
  pass "merged PR pushed to main: $(printf '%s' "$mergedpr" | cut -c1-160); HEAD=$mergecommit; branch=$branch; agent branches=$agentbranches; origin/main synced; commits: $(printf '%s' "$commits" | tr '\n' ';' | cut -c1-140)"
elif [ "$agentbranches" -eq 0 ]; then
  unverified "no PR detected (gh unavailable or not yet opened); branch=$branch; agent branches=0; recent commits: $(printf '%s' "$commits" | tr '\n' ';' | cut -c1-160)"
else
  fail "agent branches=$agentbranches exist but no PR found or main not pushed; branch=$branch; aheadbehind=$aheadbehind; commits: $(printf '%s' "$commits" | tr '\n' ';' | cut -c1-160)"
fi
