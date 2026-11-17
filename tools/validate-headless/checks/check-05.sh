#!/usr/bin/env bash
# R5: pure enum + reducer state machine (collapsed/compose/listening/thinking/answer,
#     meetingLive/meetingEnded, history/settings, error/permission variants).
# PASS requires the state tokens AND a real reducer/flow XCTest exercise.
source "$(dirname "$0")/_lib.sh"
island="$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland"
red="$island/IslandReducer.swift"
all="$island"
states=$(grep -rhoE '\b(collapsed|compose|thinking|meetingLive|meetingEnded|permissionDenied|error)\b' "$all" 2>/dev/null | sort -u | paste -sd, -)
old_only=$(grep -rhoE '\b(handsFree|notice|undo)\b' "$all" 2>/dev/null | sort -u | paste -sd, -)

ex=$(test_exercise "Packages/L3-Features/FeatureIsland" "IslandFlowTests|IslandReducerTests" "reducer-flow") && exok=1 || exok=0
if [ -n "$states" ] && [ "$exok" -eq 1 ]; then
  pass "state tokens={$states}; reducer file=$([ -f "$red" ] && echo yes || echo no); legacy tokens={$old_only}; EXERCISED reducer/flow: $ex"
else
  fail "state tokens='${states:-none}' exercise_ok=$exok; $ex (legacy={$old_only})"
fi
