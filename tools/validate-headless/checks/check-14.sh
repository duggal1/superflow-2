#!/usr/bin/env bash
# R14: Settings icon expands Island in place; port every old setting except key picker;
#      grouped Capture/Model/Prompts/Permissions/About; permission states with fix buttons.
# PASS requires the settings source AND a real settings-render XCTest exercise.
source "$(dirname "$0")/_lib.sh"
island="$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland"
src="$island $ROOT/Packages/L3-Features/FeatureSettings/Sources $ROOT/App/SuperflowApp/Sources"
icon=$(grep -rniE 'gear|settings.*icon|openSettings|settings' "$island" 2>/dev/null | wc -l | tr -d ' ')
groups=$(grep -rniE 'Capture|Model|Prompts|Permissions|About' $src 2>/dev/null | wc -l | tr -d ' ')
permfix=$(grep -rniE 'PermissionCenter|fix|Enable|Open Settings|authorizationStatus' $src 2>/dev/null | wc -l | tr -d ' ')

ex=$(test_exercise "Packages/L3-Features/FeatureSettings" "Settings" "settings-render") && exok=1 || exok=0
if [ "$icon" -gt 0 ] && [ "$groups" -gt 0 ] && [ "$permfix" -gt 0 ] && [ "$exok" -eq 1 ]; then
  pass "in-Island settings refs=$icon; group headings=$groups; permission/fix refs=$permfix; EXERCISED settings render suite: $ex"
else
  fail "settingsIcon=$icon groups=$groups permissionFix=$permfix exercise_ok=$exok; $ex"
fi
