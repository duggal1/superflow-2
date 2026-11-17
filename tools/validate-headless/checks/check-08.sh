#!/usr/bin/env bash
# R8: delete trigger-key picker; migrate/clear stored trigger preference.
# PASS requires picker gone AND a real migration XCTest exercise proving the stale key is cleared.
source "$(dirname "$0")/_lib.sh"
all="$ROOT/Packages/L3-Features/FeatureSettings/Sources $ROOT/App/SuperflowApp/Sources"
picker=$(grep -rlE 'IntelligenceTriggerKey|selectedIntelligenceTriggerKey|intelligence\.trigger' $all 2>/dev/null | grep -v '/.build/' | wc -l | tr -d ' ')

ex=$(test_exercise "App/SuperflowApp" "ClearlyInputMigrationTests" "trigger-migration") && exok=1 || exok=0
if [ "$picker" -eq 0 ] && [ "$exok" -eq 1 ]; then
  pass "trigger-key picker symbols absent (files=$picker); EXERCISED migration suite (legacy trigger preference cleared, idempotent, unrelated settings kept): $ex"
elif [ "$picker" -eq 0 ]; then
  fail "picker gone (files=0) but migration test did not pass: $ex"
else
  fail "trigger-key picker still present in $picker file(s): $(grep -rlE 'IntelligenceTriggerKey|selectedIntelligenceTriggerKey|intelligence\.trigger' $all 2>/dev/null | grep -v '/.build/' | head -4 | tr '\n' ' ')"
fi
