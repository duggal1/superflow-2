#!/usr/bin/env bash
# R21: commit/push per git.yaml (6-12 word messages); open a PR and do NOT merge.
source "$(dirname "$0")/_lib.sh"
cd "$ROOT" || unverified "cannot cd to repo root"
branch=$(git branch --show-current 2>/dev/null)
commits=$(git log -8 --pretty='%h|%s' 2>/dev/null)
# Multi-agent rule: agent/<id> branches expected when 3+ agents work.
agentbranches=$(git branch -a 2>/dev/null | grep 'agent/' | wc -l | tr -d ' ')
pr=$(gh pr list --state open --json number,title,headRefName 2>/dev/null || echo "")
if [ -n "$pr" ] && [ "$pr" != "[]" ]; then
  pass "open PR found: $(printf '%s' "$pr" | cut -c1-180); branch=$branch; agent branches=$agentbranches; recent commits: $(printf '%s' "$commits" | tr '\n' ';' | cut -c1-160)"
elif [ "$agentbranches" -eq 0 ]; then
  unverified "no open PR detected (gh unavailable or not yet opened); branch=$branch; agent branches=0; recent commits: $(printf '%s' "$commits" | tr '\n' ';' | cut -c1-160)"
else
  fail "agent branches=$agentbranches exist but no open PR found; branch=$branch; commits: $(printf '%s' "$commits" | tr '\n' ';' | cut -c1-160)"
fi
