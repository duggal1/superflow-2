#!/usr/bin/env bash
# R10: typed input — click collapsed Island, exact placeholder, Enter sends, streamed answer,
#      Copy, Esc collapses. PASS requires UI source AND a real compose XCTest exercise.
source "$(dirname "$0")/_lib.sh"
island="$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland $ROOT/Packages/L3-Features/FeatureIntelligence/Sources/SuperflowFeatureIntelligence"
ph=$(grep -rlF 'Enter any data and press Enter' $island 2>/dev/null | grep -v '/.build/' | wc -l | tr -d ' ')

ex=$(test_exercise "App/SuperflowApp" "HeadlessIntelligenceComposeTests" "typed-compose") && exok=1 || exok=0
if [ "$ph" -gt 0 ] && [ "$exok" -eq 1 ]; then
  pass "exact placeholder files=$ph; EXERCISED compose suite (typed compose streams answer + Copy, empty Enter is a no-op, cancel/retry, suggestion replaces answer): $ex"
else
  fail "placeholder files=$ph exercise_ok=$exok; $ex"
fi
