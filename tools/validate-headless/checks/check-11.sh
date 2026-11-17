#!/usr/bin/env bash
# R11: messy-transcript intent extraction in ONE reusable system prompt block shared
#      by PTT + meeting; ignore fillers/speaker labels, infer intent, use screen context.
# PASS requires the shared-block source AND a real XCTest exercise proving one block is reused.
source "$(dirname "$0")/_lib.sh"
p="$ROOT/Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence/Prompts.swift"
p2="$ROOT/Packages/L3-Features/FeatureIntelligence/Sources/SuperflowFeatureIntelligence/IntelligencePrompts.swift"
[ -f "$p" ] && [ -f "$p2" ] || source_only "prompt source files missing"
intent=$(cat "$p" "$p2" 2>/dev/null | grep -niE 'intent|filler|speaker label|screen context' | wc -l | tr -d ' ')

ex=$(test_exercise "App/SuperflowApp" "HeadlessIntelligencePromptTests|IntelligenceCoreTests" "shared-prompt") && exok=1 || exok=0
if [ "$intent" -ge 2 ] && [ "$exok" -eq 1 ]; then
  pass "shared intent/filler/speaker/screen-context block matches=$intent; EXERCISED shared-block test (messy block appears exactly once in ask/meeting-detection/suggestions tasks): $ex"
else
  fail "intent matches=$intent exercise_ok=$exok; $ex"
fi
