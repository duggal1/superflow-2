#!/usr/bin/env bash
# R15: History as an Island state: list, open full transcript+answers, search, delete, Copy.
# Old check grepped the deleted IslandHistory.swift (false FAIL). PASS requires the
# history implementation in its real location AND a real history XCTest exercise.
source "$(dirname "$0")/_lib.sh"
src="$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland $ROOT/Packages/L3-Features/FeatureIntelligence/Sources/SuperflowFeatureIntelligence"
state=$(grep -rniE 'case history|\.history\b' "$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland/IslandFlow.swift" 2>/dev/null | wc -l | tr -d ' ')
search=$(grep -rniE 'searchable|search' $src 2>/dev/null | wc -l | tr -d ' ')
delete=$(grep -rniE 'delete' $src 2>/dev/null | wc -l | tr -d ' ')
copy=$(grep -rniE 'copy' $src 2>/dev/null | wc -l | tr -d ' ')

ex=$(test_exercise "App/SuperflowApp" "HeadlessIntelligenceHistoryTests" "history") && exok=1 || exok=0
if [ "$state" -gt 0 ] && [ "$search" -gt 0 ] && [ "$delete" -gt 0 ] && [ "$copy" -gt 0 ] && [ "$exok" -eq 1 ]; then
  pass "history-as-state refs=$state; search=$search delete=$delete copy=$copy; EXERCISED history suite (list/open/search/delete/copy, case-insensitive search, missing-item no-ops): $ex"
else
  fail "historyState=$state search=$search delete=$delete copy=$copy exercise_ok=$exok; $ex"
fi
