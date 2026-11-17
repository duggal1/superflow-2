#!/usr/bin/env bash
# R13: prompt/theme selector enumerates EVERY source theme (General Meeting = "normal",
#      Coding Interview, Sales Call, Journal/Personal, Custom); nothing dropped; persists.
# The old check demanded a literal "general" case — a FALSE FAIL: "normal" is labelled
# "General Meeting". PASS requires the real theme labels AND a real XCTest exercise.
source "$(dirname "$0")/_lib.sh"
p="$ROOT/Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence/Prompts.swift"
[ -f "$p" ] || source_only "Prompts.swift missing"
mode=$(grep -nE 'enum MeetingMode|case ' "$p" 2>/dev/null | head -40)
found=(); miss=()
for kw in 'normal' 'codingInterview' 'sales' 'journal' 'custom'; do
  if printf '%s' "$mode" | grep -q "$kw"; then found+=("$kw"); else miss+=("$kw"); fi
done
labels=$(grep -rniE 'General Meeting|Coding Interview|Sales Call|Journal' "$ROOT/Packages/L3-Features/FeatureIntelligence/Sources" 2>/dev/null | head -5 | tr '\n' ' ')

ex=$(test_exercise "App/SuperflowApp" "HeadlessIntelligencePromptTests" "theme-selector") && exok=1 || exok=0
if [ ${#miss[@]} -eq 0 ] && [ "$exok" -eq 1 ]; then
  pass "MeetingMode cases=$(join_ev "${found[@]}") (normal=General Meeting); labels: {$labels}; EXERCISED selector enumeration + known real names + persistence: $ex"
else
  fail "MeetingMode cases missing={$(join_ev "${miss[@]:-none}")} present={$(join_ev "${found[@]}")} exercise_ok=$exok; $ex"
fi
