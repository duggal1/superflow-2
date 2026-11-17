#!/usr/bin/env bash
# R17: stealth — sharingType .none on EVERY window; verifier with positive control;
#      honest Verified/Failed/Unverified; WindowServer dump script; compatibility matrix;
#      no private APIs. PASS requires the source AND a real stealth XCTest exercise.
source "$(dirname "$0")/_lib.sh"
app="$ROOT/App/SuperflowApp/Sources"
none=$(grep -rnE 'sharingType *= *\.none' "$app" 2>/dev/null | wc -l | tr -d ' ')
guard=$(grep -rniE 'WindowGuard|didUpdateNotification|NSApp\.windows' "$app" 2>/dev/null | wc -l | tr -d ' ')
stealthsrc="$ROOT/Packages/L1-Adapters/ClearlyStealth/Sources"
verif=$(grep -rniE 'StealthVerifier|positive control|SCScreenshotManager|matched' "$app" "$stealthsrc" 2>/dev/null | grep -v '/.build/' | wc -l | tr -d ' ')
private=$(grep -rnE 'CGS|SLS|CGWindowSet' "$app" 2>/dev/null | grep -vE 'CGWindowList|CGPreflight|CGRequest|CGEvent' | wc -l | tr -d ' ')
matrix=$([ -f "$ROOT/docs/stealth-compatibility.md" ] && echo yes || echo no)
dump=$([ -f "$ROOT/tools/validate-headless/window-share-dump.swift" ] && echo yes || echo no)

ex=$(test_exercise "Packages/L1-Adapters/ClearlyStealth" "Verifier|WindowGuard|Status|Classifier" "stealth") && exok=1 || exok=0
if [ "$none" -gt 0 ] && [ "$guard" -gt 0 ] && [ "$verif" -gt 0 ] && [ "$matrix" = yes ] && [ "$dump" = yes ] && [ "$private" -eq 0 ] && [ "$exok" -eq 1 ]; then
  pass "sharingType(.none)=$none WindowGuard=$guard verifier/positive-control=$verif privateAPIhits=$private matrix=$matrix dumpScript=$dump; EXERCISED stealth suites (verified/failed/unverified classification, build-matched records, exclusion): $ex"
else
  fail "none=$none guard=$guard verifier=$verif privateAPIhits=$private matrix=$matrix dump=$dump exercise_ok=$exok; $ex"
fi
