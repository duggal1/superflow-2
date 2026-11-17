#!/usr/bin/env bash
# R3: delete old Island UI layer, rebuild clean, reuse backend behind thin view model.
# PASS requires BOTH source structure AND a real XCTest exercise of the rebuilt flow.
source "$(dirname "$0")/_lib.sh"
island="$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland"
backend=(
  "Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence/MeetingIntelligence.swift"
  "Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence/ScreenReader.swift"
  "Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence/ReflectionClient.swift"
  "Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence/TranscriptBuffer.swift"
  "Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence/Prompts.swift"
)
missing=(); for b in "${backend[@]}"; do [ -f "$ROOT/$b" ] || missing+=("$(basename "$b")"); done
vm=0; [ -f "$island/IslandModel.swift" ] && vm=1
legacy=$(grep -rlE 'IslandDragPolicy|showIdlePill|island\.origin' "$island" 2>/dev/null | wc -l | tr -d ' ')

ex=$(test_exercise "Packages/L3-Features/FeatureIsland" "IslandFlowTests" "rebuilt-island-flow") && exok=1 || exok=0
if [ "$vm" -eq 1 ] && [ ${#missing[@]} -eq 0 ] && [ "$exok" -eq 1 ]; then
  pass "thin view model=IslandModel.swift (reducer=$([ -f "$island/IslandReducer.swift" ] && echo yes || echo no)); backend files intact=$(join_ev "${backend[@]##*/}"); legacy-policy refs=$legacy; EXERCISED rebuilt flow: $ex"
else
  fail "view model=$vm backend_missing=$(join_ev "${missing[@]:-none}") exercise_ok=$exok; $ex"
fi
