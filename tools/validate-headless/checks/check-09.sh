#!/usr/bin/env bash
# R9: Left Control meeting toggle; transcription default ON; question-detection sensitivity
#     constant; silence -> nothing; 4-5 clickable suggestions that answer; saved to History.
# PASS requires the source tokens AND real gesture + utterance XCTest exercises.
source "$(dirname "$0")/_lib.sh"
src="$ROOT/Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence"
gest="$ROOT/Packages/L2-Engines/GestureKit/Sources/SuperflowGestureKit"
lc=$(grep -rniE 'leftControl|meetingToggle|ctrlTap' "$ROOT/Packages/L1-Adapters/ClearlyInput/Sources" "$gest" 2>/dev/null | wc -l | tr -d ' ')
sens=$(grep -rniE 'sensitiv|questionThreshold|question.*constant' "$src" "$ROOT/Packages/L3-Features/FeatureIntelligence/Sources" 2>/dev/null | wc -l | tr -d ' ')
sugg=$(grep -rniE 'suggestion' "$src" "$ROOT/Packages/L3-Features/FeatureIsland/Sources" "$ROOT/Packages/L3-Features/FeatureIntelligence/Sources" 2>/dev/null | wc -l | tr -d ' ')

ex=$(test_exercise "App/SuperflowApp" "ClearlyInputGestureTests|HeadlessIntelligenceUtteranceTests" "meeting-utterance") && exok=1 || exok=0
if [ "$lc" -gt 0 ] && [ "$sens" -gt 0 ] && [ "$sugg" -gt 0 ] && [ "$exok" -eq 1 ]; then
  pass "Left-Control/ctrlTap refs=$lc; sensitivity refs=$sens; suggestion refs=$sugg; EXERCISED ctrl-toggle + utterance suites (silence/filler→nothing, sensitivity, repeated utterances): $ex"
else
  fail "Left-Control=$lc sensitivity=$sens suggestions=$sugg exercise_ok=$exok; $ex"
fi
