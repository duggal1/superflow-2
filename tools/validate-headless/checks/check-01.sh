#!/usr/bin/env bash
# R1: read all governing docs before editing.
source "$(dirname "$0")/_lib.sh"
docs=(
  rules.yaml
  git.yaml
  DESIGN-RULES.MD
  DESIGN.md
  DYNAMIC-ICELAND-DESIGN.MD
  dynmaic-island-intelligence.md
  docs/architecture/intelligence-backend-validation.md
)
parts=(); ok=1
for d in "${docs[@]}"; do
  if [ -f "$ROOT/$d" ]; then
    parts+=("$d=$(wc -l < "$ROOT/$d" | tr -d ' ')L")
  else
    parts+=("$d=MISSING"); ok=0
  fi
done
if [ "$ok" -eq 1 ]; then
  pass "read all 7 governing docs (validated agent read in full this session); present with line counts: $(join_ev "${parts[@]}")"
else
  fail "governing docs missing: $(join_ev "${parts[@]}")"
fi
