#!/usr/bin/env bash
# R2: five sub-agents launched with disjoint file ownership.
# Process claim — source evidence only; cannot PASS (no runtime exercise).
source "$(dirname "$0")/_lib.sh"
p="$ROOT/.proof/progress.md"
if [ ! -f "$p" ]; then source_only "progress.md missing"; fi
line=$(grep -iE 'launch(ed|ing)? agents? 1-5|agents? 1-5|five sub-agents' "$p" | tail -1)
disjoint=$(grep -i 'disjoint' "$p" | tail -1)
if [ -n "$line" ] && [ -n "$disjoint" ]; then
  source_only "process claim in .proof/progress.md only: \"$(printf '%s' "$line" | cut -c1-120)\"; ownership: \"$(printf '%s' "$disjoint" | cut -c1-90)\" — five-agent dispatch/ownership not independently exercisable"
elif [ -n "$line" ]; then
  source_only "five-agent launch recorded but disjoint ownership not stated in progress.md: $(printf '%s' "$line" | cut -c1-120)"
else
  source_only "no independently verifiable evidence of five sub-agents in .proof/progress.md"
fi
